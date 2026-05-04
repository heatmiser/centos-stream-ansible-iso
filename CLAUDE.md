# CentOS Stream 10 MIN-Live ISO Builder

## Project Overview

This project creates customized CentOS Stream 10 minimal live ISOs for bare metal automation with Ansible. Built on top of the upstream CentOS SIG Alt Images project with local customizations for automation workflows.

**Profile:** MIN-Live-Automation - A truly minimal live ISO without the Anaconda installer, optimized for automation use cases only.

## Purpose

Generate bootable UEFI live ISOs with:
- SSH server enabled from boot
- Python3 for Ansible automation
- Configurable user with SSH key/password authentication
- Passwordless sudo access
- Fully containerized, portable build process
- No installer (automation-only use case)

## Architecture

### Repository Structure

```
centos-sig-alt-images/                    # Project root (not a git repo)
├── kiwi-descriptions/                    # Git subproject (upstream c10s branch)
│   ├── config.sh                         # MODIFIED: Custom user configuration
│   ├── components/
│   │   └── desktop-environments.xml      # MODIFIED: Added openssh-server, python3, sudo
│   └── [other upstream files]
├── build-live-image.sh                   # Wrapper script for containerized builds
├── live-image.conf.example               # Configuration template
├── live-image-vault.yml.example          # Ansible Vault template
├── README-BUILD.md                       # Complete build documentation
└── .gitignore                            # Excludes sensitive files
```

### Key Modifications

**Modified Files:**
1. `kiwi-descriptions/config.sh` (lines 147-183)
   - Reads `/etc/liveimage-credentials.conf` for user configuration
   - Creates user with configurable username (default: ansible)
   - Configures SSH keys and/or password authentication
   - Adds user to wheel group with passwordless sudo
   - Enables sshd service
   - Updates autologin for custom username

2. `kiwi-descriptions/components/desktop-environments.xml` (lines 71-76)
   - Added packages to MIN-Desktop profile:
     - openssh-server
     - python3
     - sudo

**New Files Created:**
3. `kiwi-descriptions/components/minlive-boot.xml`
   - New minimal live boot profile (replaces LiveInstall for automation use case)
   - ISO preferences: firmware, bootloader, mediacheck
   - Essential live packages: dracut-live, livesys-scripts, kernel, isomd5sum
   - **Excludes installer**: No anaconda, no language packs, no install environment
   - Result: ~200-250 MB smaller ISO optimized for automation

**Profile Changes:**
4. `kiwi-descriptions/platforms/workstation.xml`
   - Changed MIN-Live to MIN-Live-Automation
   - Now requires MinLiveBoot instead of LiveInstall

### Build Process

**Container-Native Architecture:**
- **Ansible Container** (`quay.io/ansible/creator-ee:latest`) - Decrypts Ansible Vault
- **CentOS Stream 10 Container** (`quay.io/centos/centos:stream10-development`) - Runs kiwi-ng build

**Workflow:**
1. Load `live-image.conf` (plaintext config)
2. Decrypt `live-image-vault.yml` (if exists) using Ansible container
3. Merge configuration and create credential injection file
4. Run kiwi-ng build in CentOS Stream 10 container
5. Clean up temporary credential files and intermediate build artifacts
6. Output ISO to `outdir/`
   - `CentOS-Stream-MIN-Live-Automation.x86_64-10.iso` - Bootable UEFI ISO
   - `CentOS-Stream-MIN-Live-Automation.x86_64-10.packages` - Package list
   - `CentOS-Stream-MIN-Live-Automation.x86_64-10.verified` - ISO checksums

## Configuration

### Plaintext Configuration (live-image.conf)

```bash
LIVE_USERNAME="ansible"                    # User account name
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"  # SSH public key file
LIVE_USER_GROUPS="wheel"                   # Additional groups
```

### Encrypted Credentials (live-image-vault.yml)

```yaml
live_user_password_hash: "$6$..."         # Password hash
additional_ssh_keys:                       # Additional SSH keys
  - "ssh-rsa AAA..."
```

## Usage

### Prerequisites

- Podman installed (works on Linux/Mac/Windows WSL2)
- No other dependencies required

### Quick Start

```bash
# Create configuration
cp live-image.conf.example live-image.conf
vi live-image.conf

# Generate SSH key (optional)
mkdir -p keys
ssh-keygen -t ed25519 -f keys/automation -N ""

# Build ISO
./build-live-image.sh

# Output: outdir/*.iso
```

### With Ansible Vault

```bash
# Create and encrypt vault
cp live-image-vault.yml.example live-image-vault.yml
# Edit with real credentials
vi live-image-vault.yml

# Encrypt
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault encrypt /work/live-image-vault.yml

# Build (prompts for vault password)
./build-live-image.sh
```

## Security

### Build Process Hardening

The build system implements multiple security layers to protect against compromise:

**Container Image Integrity:**
- **ALL** container images pinned to SHA256 digests (not mutable tags)
- Prevents supply chain attacks via image substitution
- Digest verification after pull to detect tampering

**Critical Security Consideration - Ansible Container:**
The Ansible container (`quay.io/ansible/creator-ee`) has access to your **decrypted vault secrets** in plaintext, including:
- Vault password (if using password file)
- Decrypted password hashes
- SSH keys from vault

**Protection measures:**
- Pinned to SHA256 digest: `sha256:a03e8311cc722be36a81e8c9aa61ee8f65b535ddfbf16d65b6eadc99b720fa24`
- **Strict digest verification** - build fails if digest doesn't match (not just warning)
- **Network isolation** - runs with `--network=none` to prevent exfiltration
- Vault decryption is a local crypto operation and doesn't require network access

**Build container (CentOS Stream 10):**
- Pinned to SHA256 digest: `sha256:f55f0785fbe24a765d263202a26ce6f14537f2201dc30f89d92ba03ba6ff41e5`
- Digest verification with warning on mismatch
- Network access required for package installation from repositories

**Configuration Safety:**
- Safe configuration parsing without `source` command
- Prevents arbitrary code execution from config files
- Variable name validation (alphanumeric + underscore only)
- Applied to both `build-live-image.sh` and `config.sh`

**Container Isolation:**
- KIWI descriptions mounted read-only in container (`:ro` flag)
- SELinux isolation enabled (`:z` flag)
- Container breakout monitoring via directory tracking
- Privileged mode required only for loop devices, mount, chroot operations

**Credential Security:**
- **Credentials at rest**: Encrypted with Ansible Vault (AES256)
- **Credentials in transit**: Injected as temporary file, deleted after build
- **Exposure window**: Only during build (~15-30 minutes)
- **File permissions**: 600 (owner read/write only)

**Authentication:**
- **SSH authentication**: Key-based preferred, password fallback supported
- **Sudo access**: Passwordless for wheel group (automation requirement)

### Security Tradeoffs

**Privileged Container:**
- Required for KIWI's loop device, mount, and chroot operations
- Mitigated by: SHA256 pinning, read-only mounts, SELinux, monitoring
- Alternative: Run on dedicated build host with limited access

**Upstream Trust:**
- Trusts CentOS Stream repositories for package installation
- Trusts upstream KIWI descriptions from CentOS SIG Alt Images
- Mitigated by: Using official Red Hat/CentOS infrastructure

### Files Never to Commit

- `live-image.conf` (may contain non-sensitive config, but user-specific)
- `live-image-vault.yml` (encrypted credentials)
- `kiwi-descriptions/root/etc/liveimage-credentials.conf` (temporary)
- `outdir/*` (build artifacts)
- `keys/*` (SSH keys)

All protected by `.gitignore`.

### Updating Container Digests

When updating to newer container images:

**CentOS Stream 10 Build Container:**
```bash
# Pull latest
podman pull quay.io/centos/centos:stream10-development

# Get new digest
podman inspect quay.io/centos/centos:stream10-development --format '{{.Digest}}'

# Update CENTOS_CONTAINER in build-live-image.sh with new digest
# Update expected_digest in pull_containers() function
# Test build, then commit
```

**Ansible Creator EE Container (CRITICAL - handles vault secrets):**
```bash
# Pull latest
podman pull quay.io/ansible/creator-ee:latest

# Get new digest
podman inspect quay.io/ansible/creator-ee:latest --format '{{.Digest}}'

# Update ANSIBLE_CONTAINER in build-live-image.sh with new digest
# Update expected_digest in decrypt_vault() function
# Test vault decryption, then commit
```

**⚠️ IMPORTANT:** Always verify the source and integrity of new container images before pinning, especially the Ansible container which has access to decrypted secrets.

## Upstream Sync

The `kiwi-descriptions/` directory is a git checkout of the upstream c10s branch:
- **Upstream**: https://pagure.io/centos-sig-alt-images/kiwi-descriptions (c10s branch)
- **Local modifications**: config.sh and components/desktop-environments.xml

To sync with upstream:
```bash
cd kiwi-descriptions
git fetch origin
git merge origin/c10s
# Resolve conflicts, preserving our modifications to config.sh and desktop-environments.xml
```

## Development Notes

### Adding Packages

Edit `kiwi-descriptions/components/desktop-environments.xml`, MIN-Desktop profile:
```xml
<package name="your-package-name"/>
```

### Modifying User Configuration

Edit `kiwi-descriptions/config.sh`, MIN-Live section (starts around line 147).

### Testing Changes

See README-BUILD.md for complete testing procedures including:
- ISO boot verification (requires UEFI boot - OVMF firmware)
- SSH access testing
- Ansible connectivity testing

**Quick Test:**
```bash
# Boot in QEMU with UEFI
qemu-system-x86_64 -m 2048 -machine q35 -enable-kvm -cpu host \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
  -cdrom outdir/CentOS-Stream-MIN-Live-Automation.x86_64-10.iso -boot d \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0

# Test SSH (from another terminal)
ssh -i keys/automation -p 2222 ansible@localhost 'sudo whoami'
```

## Standards and Conventions

### Ansible Code
When generating Ansible playbooks for testing or automation:
- Use FQCN (Fully Qualified Collection Names)
- Prefer `ansible.builtin` prefix over short module names
- Use `vars_files` over inline vars
- Check syntax with ansible-lint
- Follow https://github.com/redhat-cop/automation-good-practices/

### Shell Scripts
- Use `set -euo pipefail` for safety
- Include help text and usage examples
- Provide colored output for readability
- Validate inputs before execution

## Troubleshooting

### Build Issues

```bash
# Check Podman
podman ps

# Check disk space (need ~5GB)
df -h

# Clean Podman storage
podman system prune -a
```

### Credential Issues

```bash
# Test vault decryption
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault view /work/live-image-vault.yml
```

See README-BUILD.md for complete troubleshooting guide.

## License

Inherits GPL-3.0 from upstream CentOS SIG Alt Images project.

## References

- Upstream KIWI descriptions: https://pagure.io/centos-sig-alt-images/kiwi-descriptions
- CentOS SIG Alt Images: https://sigs.centos.org/altimages/
- DIY Local Images docs: https://sigs.centos.org/altimages/diy-local-images/
- KIWI NG documentation: https://osinside.github.io/kiwi/
- Ansible best practices: https://github.com/redhat-cop/automation-good-practices/
