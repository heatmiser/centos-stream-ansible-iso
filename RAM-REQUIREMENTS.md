# RAM Requirements for Live ISO Deployments

## Why the Vendor Minimum Does Not Apply

CentOS Stream 10 documentation states a 1.5 GB RAM minimum. That figure targets the
Anaconda graphical installer running a full desktop session simultaneously with the
package manager. Neither of those components exists in this project's live ISOs. The
figure is a reasonable starting point for planning a traditional installation; it is
not meaningful for sizing bare-metal nodes that will boot a minimal automation ISO.

## How dmsquash-live Uses RAM

This project's ISOs are built with `flags="dmsquash"` and an erofs compressed
filesystem. Understanding how dmsquash-live actually loads the image is essential for
accurate sizing.

### What does NOT happen

The erofs image is not copied wholesale into RAM at boot. A common assumption is that
a live ISO must fit entirely in memory — this is only true when the `rd.live.ram=1`
kernel parameter is explicitly set.

### What does happen

At boot, the compressed erofs image stays on the block device (the ISO itself,
accessed via a loop device). The kernel loads only what it needs, on demand, via the
normal page cache — the same mechanism used for any filesystem on a disk-based
install. Under memory pressure those cached pages are evicted and re-read from the
block device, exactly as they would be from a hard drive or SSD.

A **writable overlay (tmpfs)** is layered on top of the read-only erofs image via
device mapper. This overlay lives entirely in RAM. Every write made during the live
session — log entries, temp files, runtime state written by services or Ansible tasks
— is stored in the overlay rather than on a disk. When the system reboots the overlay
is discarded.

### The key difference from a disk-based install

On a traditional disk install, writes go to the filesystem on the storage device and
consume disk space. On a live ISO, writes go to the tmpfs overlay and consume RAM.
The disk install has effectively unlimited write capacity (bounded by disk size); the
live ISO has write capacity bounded by available RAM. There is no swap configured by
default on a live system, so this boundary is firm.

## Practical RAM Estimates for This Project

Both profiles in this project (`MIN-Live-Automation` and `MIN-Live-Auto-Cloud`) are
text-mode, automation-only ISOs with no installer and no desktop environment. The
intended workload is: boot → SSH ready → Ansible automation executes from a
controller → phone-home job polling runs locally.

In this model, the node running the live ISO is mostly a target, not an orchestrator.
The Ansible control plane runs on the controller; the node side receives tasks, runs
small local commands, and writes modest amounts of result data to the tmpfs overlay.

| Profile | Minimum | Comfortable |
|---|---|---|
| MIN-Live-Automation | 512 MB | 768 MB |
| MIN-Live-Auto-Cloud | 768 MB | 1 GB |

`MIN-Live-Auto-Cloud` carries a slightly higher floor because cloud-init runs its
full module chain at boot — writing instance data, network configuration, and log
output to the overlay before the system becomes available. The additional overhead is
modest but real.

### What determines the practical floor

Two factors set the real minimum for any given deployment:

1. **Kernel + essential services fit in RAM.** For our minimal profile this means the
   kernel, sshd, python3, and any enabled systemd units (cloud-init modules in the
   cloud variant, dcm-phone-home in automation scenarios). This is well under 256 MB.

2. **The overlay has enough headroom for the session's writes.** For hardware
   discovery and install-trigger workflows this is small — tens of megabytes at most.
   If Ansible tasks write large temporary files locally (staging artifacts, expanding
   archives) the overlay can grow substantially. Operators should account for the
   expected write volume of their specific automation workload.

## Tuning Options

### Overlay size

The default overlay size is set by dracut-live and varies by version; it is typically
in the range of 512 MB or 50% of available RAM, whichever is smaller. This can be
set explicitly via kernel command line:

```
rd.live.overlay.size=2048
```

The value is in megabytes. This can be added to the `kernelcmdline` attribute in
`kiwi-descriptions/components/minlive-boot.xml` to bake it into the build.

### Full RAM copy

Setting `rd.live.ram=1` causes the entire erofs image to be decompressed and copied
into RAM at boot. This eliminates all block device reads after boot (faster, no ISO
required after initial load) at the cost of a much higher baseline RAM requirement.
The decompressed image is significantly larger than the compressed ISO file on disk.
This mode is not recommended for this project's use case — the automation workloads
run over SSH and do not benefit from the read latency reduction, and it rules out
deployment on lower-memory nodes.

## Summary

| Consideration | Live ISO | Disk-based install |
|---|---|---|
| Filesystem reads | Page cache, evictable | Page cache, evictable |
| Writes | tmpfs overlay — consumes RAM | Filesystem — consumes disk |
| Swap | Not configured by default | Available if provisioned |
| Effective write limit | Available RAM minus overlay size | Available disk space |
| Vendor 1.5 GB minimum | Not applicable (targets installer) | Applicable |
