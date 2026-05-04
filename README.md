# CentOS Stream Ansible ISO Builder

Portable, containerized build system for creating customized CentOS Stream text-only live ISOs designed for bare metal automation with Ansible.

**Current Status**: Supports CentOS Stream 10. Support for other CentOS Stream versions (9, future releases) is planned as a work in progress.

## Features

- 🔧 **Text-only live environment** - Minimal footprint, fast boot
- 🔐 **SSH server enabled** - Remote access from first boot
- 🐍 **Python3 included** - Ready for Ansible automation
- 👤 **Configurable user** - Custom username, SSH key, and/or password
- 🔓 **Passwordless sudo** - Full root access for automation workflows
- 📦 **Fully containerized** - Works on any system with Podman (Linux/Mac/Windows WSL2)
- 🔒 **Ansible Vault integration** - Secure credential management
- ⚡ **Zero dependencies** - Only Podman required on host

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/YOUR_USERNAME/centos-stream-ansible-iso.git
cd centos-stream-ansible-iso

# 2. Create configuration
cp live-image.conf.example live-image.conf
vi live-image.conf

# 3. Generate SSH key (optional)
mkdir -p keys
ssh-keygen -t ed25519 -f keys/automation -N "" -C "automation@liveiso"

# 4. Build ISO (requires Podman)
./build-live-image.sh

# 5. ISO output in outdir/
ls -lh outdir/*.iso
```

## Documentation

- **[README-BUILD.md](README-BUILD.md)** - Complete build instructions, testing, and troubleshooting
- **[CLAUDE.md](CLAUDE.md)** - Project architecture and development guide
- **[ATTRIBUTION.md](ATTRIBUTION.md)** - Upstream sources and copyright information
- **[UPSTREAM-SYNC.md](UPSTREAM-SYNC.md)** - Workflow for syncing with upstream changes

## Prerequisites

- **Podman** installed and running
  - Linux: `dnf install podman` or `apt install podman`
  - Mac: Install [Podman Desktop](https://podman.io/getting-started/installation)
  - Windows: Install Podman in WSL2

That's it! No other dependencies required.

## Usage Examples

### Basic Build (SSH Key Only)

```bash
# live-image.conf
LIVE_USERNAME="ansible"
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"

# Build
./build-live-image.sh
```

### Build with Encrypted Password

```bash
# Create vault
cat > live-image-vault.yml <<EOF
live_user_password_hash: "$(openssl passwd -6 'YourPassword')"
EOF

# Encrypt
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault encrypt /work/live-image-vault.yml

# Build (prompts for vault password)
./build-live-image.sh
```

### Test in QEMU

```bash
# UEFI boot (recommended - ISO is designed for UEFI)
qemu-system-x86_64 -m 2048 \
  -machine q35 \
  -enable-kvm \
  -cpu host \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
  -cdrom outdir/CentOS-Stream-MIN-Live-Automation.x86_64-10.iso \
  -boot d \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0

# Note: Requires OVMF firmware
# Fedora/RHEL: sudo dnf install edk2-ovmf
# Debian/Ubuntu: sudo apt install ovmf

# SSH from another terminal
ssh -i keys/automation -p 2222 ansible@localhost
```

## Configuration

### Plaintext Config (live-image.conf)

```bash
LIVE_USERNAME="ansible"                    # User account name
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"  # SSH public key
LIVE_USER_GROUPS="wheel"                   # Additional groups
```

### Encrypted Vault (live-image-vault.yml)

```yaml
live_user_password_hash: "$6$..."         # Password hash
additional_ssh_keys:                       # Additional SSH keys
  - "ssh-rsa AAA..."
  - "ssh-ed25519 AAA..."
```

## What Gets Built

The generated ISO includes:
- CentOS Stream 10 (minimal install)
- OpenSSH server (enabled at boot)
- Python 3.x
- Configured user with:
  - SSH access (key and/or password)
  - Passwordless sudo
  - Auto-login on console
- Network enabled (DHCP)

Perfect for:
- Bare metal provisioning
- Ansible automation
- Infrastructure bootstrapping
- PXE boot environments
- Live system recovery

## Architecture

This project wraps the [CentOS SIG Alt Images](https://sigs.centos.org/altimages/) KIWI descriptions with:
- Credential injection mechanism
- Container-native build process
- Ansible Vault integration
- Portable cross-platform support

See [CLAUDE.md](CLAUDE.md) for complete architecture details.

## Customization

### Add Packages

Edit `kiwi-descriptions/components/desktop-environments.xml`:

```xml
<packages type="image" patternType="plusRecommended" profiles="MIN-Desktop">
    <!-- Existing packages -->
    <package name="bash"/>
    <package name="openssh-server"/>
    <package name="python3"/>
    
    <!-- Add your packages -->
    <package name="vim"/>
    <package name="git"/>
    <package name="tmux"/>
</packages>
```

### Modify User Configuration

Edit `kiwi-descriptions/config.sh` in the MIN-Live section (around line 147).

See [CLAUDE.md](CLAUDE.md) for development guidelines.

## Security

- **Credentials at rest**: Encrypted with Ansible Vault
- **Build-time secrets**: Temporary injection, cleaned after build
- **SSH authentication**: Key-based preferred, password fallback supported
- **Root access**: Via sudo for automation (passwordless for wheel group)

Files automatically excluded from git (see `.gitignore`):
- `live-image.conf` (may contain sensitive paths)
- `live-image-vault.yml` (encrypted credentials)
- `keys/` (SSH keys)
- `outdir/` (build artifacts)

## Testing

```bash
# Create test configuration
cp live-image.conf.example live-image.conf
ssh-keygen -t ed25519 -f keys/test -N ""
sed -i 's|./keys/automation.pub|./keys/test.pub|' live-image.conf

# Build
./build-live-image.sh

# Test in VM
qemu-system-x86_64 -m 2048 -cdrom outdir/*.iso -boot d \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0

# Verify (from another terminal)
ssh -i keys/test -p 2222 ansible@localhost 'sudo whoami'
```

See [README-BUILD.md](README-BUILD.md) for comprehensive testing procedures.

## Upstream

Based on [CentOS SIG Alt Images - KIWI descriptions](https://pagure.io/centos-sig-alt-images/kiwi-descriptions) (c10s branch).

This is a local customization with modifications for automation use cases. We do not submit PRs upstream.

See [ATTRIBUTION.md](ATTRIBUTION.md) for detailed attribution and [UPSTREAM-SYNC.md](UPSTREAM-SYNC.md) for sync workflow.

## License

GNU General Public License v3.0

This project inherits the license from the upstream CentOS SIG Alt Images project.

See [LICENSE](LICENSE) for full text and [ATTRIBUTION.md](ATTRIBUTION.md) for copyright details.

## Support

- **Build issues**: See [README-BUILD.md](README-BUILD.md) troubleshooting section
- **Upstream KIWI issues**: https://pagure.io/centos-sig-alt-images/kiwi-descriptions/issues
- **This customization**: Open an issue in this repository

## Contributing

This is a local customization for specific automation requirements. Contributions that improve the build system, documentation, or Ansible integration are welcome.

For changes to upstream KIWI descriptions, submit to the [upstream project](https://pagure.io/centos-sig-alt-images/kiwi-descriptions).

## Acknowledgments

- **CentOS SIG Alt Images** for the upstream KIWI descriptions
- **KIWI NG** project for the image building framework  
- **CentOS Stream** for the base operating system
