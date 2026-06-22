#!/usr/bin/env bash
# dcm-collect-hardware: Full hardware manifest collector.
# Outputs a single JSON object to stdout. Called by dcm-phone-home.sh
# for the "discovery" job type. Requires root (dmidecode).
set -euo pipefail

# --- System identity (dmidecode type 0 = BIOS, type 1 = System) ---
SYS_SERIAL=$(dmidecode -t1 2>/dev/null \
    | awk -F': ' '/Serial Number/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' \
    || echo "unknown")
SYS_MANUFACTURER=$(dmidecode -t1 2>/dev/null \
    | awk -F': ' '/Manufacturer/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' \
    || echo "unknown")
SYS_MODEL=$(dmidecode -t1 2>/dev/null \
    | awk -F': ' '/Product Name/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' \
    || echo "unknown")
BIOS_VERSION=$(dmidecode -t0 2>/dev/null \
    | awk -F': ' '/Version/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' \
    || echo "unknown")

# --- Network ---
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || echo "unknown")
DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || echo "")
IPV4=""
if [ -n "${DEFAULT_IFACE}" ]; then
    IPV4=$(ip -4 addr show "${DEFAULT_IFACE}" 2>/dev/null \
        | awk '/inet / {print $2}' | cut -d/ -f1 | head -1 || echo "")
fi

# --- CPU ---
CPU_COUNT=$(lscpu 2>/dev/null | awk '/^CPU\(s\):/ {print $2}' | head -1 || echo "0")
CPU_MODEL=$(lscpu 2>/dev/null | awk -F':[[:space:]]+' '/^Model name/ {print $2; exit}' || echo "unknown")
CPU_ARCH=$(lscpu 2>/dev/null | awk -F':[[:space:]]+' '/^Architecture/ {print $2; exit}' || echo "unknown")

# --- Memory ---
MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")

# --- Build JSON via python3 for safe escaping and arithmetic ---
python3 - \
    "${SYS_SERIAL}" "${SYS_MANUFACTURER}" "${SYS_MODEL}" "${BIOS_VERSION}" \
    "${HOSTNAME_SHORT}" "${IPV4}" \
    "${CPU_COUNT}" "${CPU_MODEL}" "${CPU_ARCH}" \
    "${MEM_KB}" \
<<'PYEOF'
import json, sys, os, glob, subprocess, re

serial, manufacturer, model, bios_version, \
    hostname, ip, \
    cpu_count, cpu_model, cpu_arch, \
    mem_kb = sys.argv[1:11]

# --- System ---
system = {
    "manufacturer": manufacturer.strip(),
    "model": model.strip(),
    "bios_version": bios_version.strip(),
}

# --- CPU ---
cpu = {
    "count": int(cpu_count.strip() or "0"),
    "model": cpu_model.strip(),
    "architecture": cpu_arch.strip(),
}

# --- Memory ---
memory_gb = round(int(mem_kb.strip() or "0") / 1048576)

# --- Network interfaces ---
interfaces = []
for iface_path in sorted(glob.glob("/sys/class/net/*")):
    iface = os.path.basename(iface_path)
    if iface == "lo":
        continue
    try:
        mac = open(f"/sys/class/net/{iface}/address").read().strip()
        state = open(f"/sys/class/net/{iface}/operstate").read().strip()
        mtu = int(open(f"/sys/class/net/{iface}/mtu").read().strip())
        speed = -1
        speed_path = f"/sys/class/net/{iface}/speed"
        if os.path.exists(speed_path):
            try:
                speed = int(open(speed_path).read().strip())
            except (ValueError, OSError):
                speed = -1
        interfaces.append({"name": iface, "mac": mac, "state": state, "mtu": mtu, "speed": speed})
    except (OSError, ValueError):
        continue

# --- Disks ---
disks = []
try:
    result = subprocess.run(
        ["lsblk", "-d", "-o", "NAME,SIZE,ROTA,MODEL,VENDOR,SERIAL,WWN",
         "--json", "--bytes"],
        capture_output=True, text=True, check=True
    )
    blk_data = json.loads(result.stdout)
    for dev in blk_data.get("blockdevices", []):
        name = dev.get("name", "")
        if not name or name.startswith("loop") or name.startswith("sr"):
            continue
        size_bytes = int(dev.get("size") or 0)
        size_gb = round(size_bytes / (1024 ** 3))
        rotational = bool(int(dev.get("rota") or 0))
        by_path = ""
        matches = glob.glob(f"/dev/disk/by-path/*-{name}")
        if not matches:
            matches = glob.glob(f"/dev/disk/by-path/*{name}")
        if matches:
            by_path = os.path.basename(sorted(matches)[0])
        disks.append({
            "by_path": by_path,
            "name": name,
            "size_gb": size_gb,
            "rotational": rotational,
            "model": (dev.get("model") or "").strip(),
            "vendor": (dev.get("vendor") or "").strip(),
            "serial": (dev.get("serial") or "").strip(),
            "wwn": (dev.get("wwn") or "").strip(),
        })
except (FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError):
    disks = []

# --- GPU (optional — lspci may not be present) ---
gpu = []
try:
    result = subprocess.run(
        ["lspci", "-mm"],
        capture_output=True, text=True, check=True
    )
    gpu_counts: dict = {}
    for line in result.stdout.splitlines():
        if not any(kw in line for kw in ("VGA", "3D controller", "Display")):
            continue
        parts = re.split(r'\s+"', line, maxsplit=6)
        parts = [p.strip('"') for p in parts]
        if len(parts) >= 4:
            vendor = parts[2] if len(parts) > 2 else "unknown"
            model_name = parts[3] if len(parts) > 3 else "unknown"
            key = (vendor, model_name)
            gpu_counts[key] = gpu_counts.get(key, 0) + 1
    for (gvendor, gmodel), count in gpu_counts.items():
        gpu.append({"vendor": gvendor, "model": gmodel, "count": count})
except (FileNotFoundError, subprocess.CalledProcessError):
    gpu = []

manifest = {
    "serial": serial.strip(),
    "hostname": hostname.strip(),
    "ip": ip.strip(),
    "interfaces": interfaces,
    "disks": disks,
    "cpu": cpu,
    "memory_gb": memory_gb,
    "gpu": gpu,
    "system": system,
}

print(json.dumps(manifest))
PYEOF
