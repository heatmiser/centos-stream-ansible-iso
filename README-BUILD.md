# Building CentOS Stream 10 MIN-Live-Automation ISO

Complete guide for building a minimal CentOS Stream 10 live ISO designed for bare metal automation with Ansible.

## Overview

This build system creates a UEFI-bootable live ISO with:
- **No installer** - Automation-only use case
- **Minimal footprint** - 1.3 GB ISO (~200-250 MB smaller than standard live ISOs)
- **SSH enabled** - Remote access from first boot
- **Python3 included** - Ready for Ansible automation
- **Configurable user** - Custom username, SSH key, and/or password
- **Passwordless sudo** - Full root access for automation

**Output:** `CentOS-Stream-MIN-Live-Automation.x86_64-10.iso` (1.3 GB)

## Prerequisites

**Required:**
- Podman installed and running
  - Linux: `dnf install podman` or `apt install podman`
  - Mac: Install [Podman Desktop](https://podman.io/getting-started/installation)
  - Windows: Install Podman in WSL2

**Optional (for testing):**
- OVMF UEFI firmware for QEMU
  - Fedora/RHEL: `sudo dnf install edk2-ovmf`
  - Debian/Ubuntu: `sudo apt install ovmf`

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/heatmiser/centos-stream-ansible-iso.git
cd centos-stream-ansible-iso
```

### 2. Create Configuration

```bash
# Copy example configuration
cp live-image.conf.example live-image.conf

# Edit with your settings
vi live-image.conf
```

**Minimal configuration:**
```bash
LIVE_USERNAME="ansible"
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"
```

### 3. Generate SSH Key (if needed)

```bash
mkdir -p keys
ssh-keygen -t ed25519 -f keys/automation -N "" -C "automation@liveiso"
```

This creates:
- `keys/automation` - Private key (keep secure)
- `keys/automation.pub` - Public key (referenced in config)

### 4. Build ISO

```bash
./build-live-image.sh
```

**Build process:**
- Pulls container images (first run only)
- Installs KIWI and dependencies in container
- Builds the ISO
  - First build: ~15-30 minutes (depends on network speed)
  - Subsequent builds: ~6 minutes (with cached container images)
- Outputs to `outdir/`

**Output files:**
```
outdir/
├── CentOS-Stream-MIN-Live-Automation.x86_64-10.iso      # Bootable ISO (1.3 GB)
├── CentOS-Stream-MIN-Live-Automation.x86_64-10.packages # Package list
└── CentOS-Stream-MIN-Live-Automation.x86_64-10.verified # Checksums
```

## Configuration Options

### Plaintext Configuration (live-image.conf)

```bash
# Username for automation account
LIVE_USERNAME="ansible"

# SSH public key file path
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"

# Additional groups (comma-separated)
LIVE_USER_GROUPS="wheel"

# Password hash (optional - better to use vault)
# LIVE_USER_PASSWORD_HASH="$6$..."
```

### Encrypted Credentials (live-image-vault.yml)

For sensitive data like password hashes:

**Create vault file:**

```bash
# Copy example
cp live-image-vault.yml.example live-image-vault.yml

# Generate password hash
openssl passwd -6 'YourPassword123'

# Edit vault with real credentials
vi live-image-vault.yml
```

**Encrypt the vault:**

```bash
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault encrypt /work/live-image-vault.yml
```

**Build with vault:**

```bash
# Interactive password prompt
./build-live-image.sh

# Or use password file
echo 'vault_password' > .vault_pass
chmod 600 .vault_pass
./build-live-image.sh --vault-password-file .vault_pass
```

**Manage encrypted vault:**

```bash
# View vault contents
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault view /work/live-image-vault.yml

# Edit vault
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault edit /work/live-image-vault.yml

# Change vault password
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault rekey /work/live-image-vault.yml
```

## Authentication Methods

### SSH Key Only (Recommended)

Most secure option for automation:

```bash
# live-image.conf
LIVE_USERNAME="ansible"
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"
```

### Password Only

For interactive testing:

```bash
# live-image-vault.yml
live_user_password_hash: "$6$rounds=5000$salt$hash..."
```

### Both SSH Key and Password

Maximum flexibility:

```bash
# live-image.conf
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"

# live-image-vault.yml
live_user_password_hash: "$6$rounds=5000$salt$hash..."
```

### Multiple SSH Keys

Use vault for additional keys:

```yaml
# live-image-vault.yml
additional_ssh_keys:
  - "ssh-rsa AAAAB3... user1@host"
  - "ssh-ed25519 AAAAC3... user2@host"
```

## Testing and Verification

### Boot Test (UEFI Required)

**Important:** This ISO is designed for **UEFI boot only**. Legacy BIOS boot is not supported.

**Prerequisites:**
```bash
# Install OVMF UEFI firmware
# Fedora/RHEL:
sudo dnf install edk2-ovmf

# Debian/Ubuntu:
sudo apt install ovmf
```

**Boot the ISO:**
```bash
qemu-system-x86_64 -m 2048 \
  -machine q35 \
  -enable-kvm \
  -cpu host \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
  -cdrom outdir/CentOS-Stream-MIN-Live-Automation.x86_64-10.iso \
  -boot d \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0
```

**Boot behavior:**
- Automatically boots to first menu entry (no media test)
- Auto-login as configured user (default: `ansible`)
- SSH service starts automatically

### Console Verification

After the ISO boots, verify in the VM console:

```bash
# Check username
whoami  # Should show: ansible (or your configured username)

# Check groups
groups  # Should show: wheel

# Check SSH service
systemctl status sshd  # Should be active (running)

# Check Python
python3 --version  # Should show Python 3.x

# Check sudo (no password prompt)
sudo whoami  # Should show: root

# Test sudo privileges
sudo -l  # Should show: NOPASSWD: ALL

# Check network
ip addr  # Should have network interface with IP
```

### SSH Access Test

From your host machine (different terminal):

```bash
# Test SSH connection
ssh -i keys/automation -p 2222 ansible@localhost

# Test sudo over SSH
ssh -i keys/automation -p 2222 ansible@localhost 'sudo whoami'
# Should output: root (without password prompt)
```

### Ansible Connectivity Test

**Create test inventory:**

```bash
cat > test-inventory.yml <<EOF
all:
  hosts:
    liveiso:
      ansible_host: localhost
      ansible_port: 2222
      ansible_user: ansible
      ansible_ssh_private_key_file: ./keys/automation
EOF
```

**Test connectivity:**

```bash
# Ping test
ansible -i test-inventory.yml liveiso -m ansible.builtin.ping

# Expected output:
# liveiso | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }

# Test privileged access
ansible -i test-inventory.yml liveiso -m ansible.builtin.command \
  -a "whoami" --become

# Expected output: root
```

**Run test playbook:**

```bash
cat > test-playbook.yml <<EOF
---
- name: Test MIN-Live-Automation ISO
  hosts: liveiso
  become: true
  tasks:
    - name: Check OS distribution
      ansible.builtin.debug:
        msg: "Running on {{ ansible_distribution }} {{ ansible_distribution_version }}"

    - name: Verify Python
      ansible.builtin.command: python3 --version
      register: python_version
      changed_when: false

    - name: Show Python version
      ansible.builtin.debug:
        var: python_version.stdout

    - name: Test package installation
      ansible.builtin.dnf:
        name: vim
        state: present
      register: pkg_install

    - name: Verify package installed
      ansible.builtin.debug:
        msg: "Package installation {{ 'successful' if pkg_install.changed else 'already present' }}"
EOF

# Run playbook
ansible-playbook -i test-inventory.yml test-playbook.yml
```

## Platform-Specific Notes

### Linux (Native)

Full support with native Podman:

```bash
# Install Podman
sudo dnf install podman    # Fedora/RHEL/CentOS
sudo apt install podman    # Debian/Ubuntu

# Build and test
./build-live-image.sh
```

### macOS

Requires Podman Machine (VM backend):

```bash
# Install via Homebrew or Podman Desktop
brew install podman

# Initialize and start Podman machine
podman machine init
podman machine start

# Verify
podman ps

# Build normally
./build-live-image.sh
```

### Windows (WSL2)

Install Podman inside WSL2 distribution:

```bash
# In WSL2 terminal (Ubuntu example)
sudo apt update
sudo apt install podman

# Verify
podman ps

# Build normally
./build-live-image.sh
```

## Troubleshooting

### Podman Issues

```bash
# Check Podman status
podman ps

# Check Podman version
podman version

# On macOS: ensure Podman machine is running
podman machine list
podman machine start

# Test Podman connectivity
podman run --rm hello-world
```

### Build Failures

**Insufficient disk space:**
```bash
# Check available space (need ~3-4 GB total)
# - ISO output: 1.3 GB
# - Build artifacts during build: ~1-2 GB (cleaned up after)
# - Container images: ~500 MB - 1 GB
df -h

# Check Podman storage
podman system df

# Clean up old images/containers
podman system prune -a
```

**Container image pull failures:**
```bash
# Retry with explicit pull
podman pull quay.io/centos/centos@sha256:f55f0785fbe24a765d263202a26ce6f14537f2201dc30f89d92ba03ba6ff41e5

# Check network connectivity
ping quay.io
```

**KIWI build errors:**
- Check build logs in terminal output
- Verify configuration files are valid
- Ensure credentials file syntax is correct

### Vault Decryption Errors

```bash
# Verify vault file is encrypted
file live-image-vault.yml
# Should show: data (encrypted)

# Test decryption manually
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault view /work/live-image-vault.yml

# If decryption fails, verify password
# Re-encrypt if necessary
```

### Boot Issues

**VM doesn't boot / hangs at TianoCore:**
- Ensure using correct QEMU command with OVMF firmware
- Check that `-machine q35` is specified
- Verify OVMF package is installed

**GRUB errors:**
- This should not occur with current build
- If seen, report as issue with error details

**Network not available in VM:**
```bash
# In VM console
ip addr  # Check for interface
systemctl status NetworkManager
nmcli device status
```

**SSH connection refused:**
```bash
# In VM console
systemctl status sshd
journalctl -u sshd -n 50

# On host
ssh -vvv -i keys/automation -p 2222 ansible@localhost
```

### SSH Key Issues

**Permission denied (publickey):**
```bash
# Check SSH key permissions
ls -la keys/
chmod 600 keys/automation      # Private key
chmod 644 keys/automation.pub  # Public key

# Verify key format
ssh-keygen -l -f keys/automation.pub

# Test SSH with verbose output
ssh -vvv -i keys/automation -p 2222 ansible@localhost
```

**Wrong key loaded:**
```bash
# Explicitly specify key (ignore ssh-agent)
ssh -o IdentitiesOnly=yes -i keys/automation -p 2222 ansible@localhost
```

## Advanced Usage

### Custom Packages

Edit `kiwi-descriptions/components/desktop-environments.xml` in the MIN-Desktop section:

```xml
<packages type="image" patternType="plusRecommended" profiles="MIN-Desktop">
    <!-- Existing packages -->
    <package name="bash"/>
    <package name="openssh-server"/>
    <package name="python3"/>
    <package name="sudo"/>

    <!-- Add your packages here -->
    <package name="vim"/>
    <package name="git"/>
    <package name="tmux"/>
    <package name="htop"/>
</packages>
```

After editing, rebuild the ISO.

### Custom User Groups

```bash
# live-image.conf
LIVE_USER_GROUPS="wheel,docker,libvirt,kvm"
```

Groups must exist in the base image or be created in `config.sh`.

## Security Considerations

### Credentials

1. **SSH Keys**
   - Use ed25519 keys (stronger than RSA)
   - Keep private keys secure (never commit to git)
   - Use different keys per environment

2. **Passwords**
   - Always use strong passwords with Ansible Vault
   - Never commit unencrypted vaults
   - Rotate vault passwords regularly

3. **Vault Files**
   - Never commit decrypted `live-image-vault.yml`
   - Never commit `.vault_pass` files
   - Use `.gitignore` to prevent accidents

### Build Artifacts

Files automatically excluded from git (`.gitignore`):
- `live-image.conf` (may contain paths)
- `live-image-vault.yml` (encrypted credentials)
- `kiwi-descriptions/root/etc/liveimage-credentials.conf` (temporary)
- `outdir/*` (build artifacts)
- `keys/*` (SSH keys)

### Container Security

The build system implements multiple security layers:
- Container images pinned to SHA256 digests
- KIWI descriptions mounted read-only
- Network isolation for vault decryption
- SELinux isolation enabled
- Safe configuration parsing (no code execution)

See `CLAUDE.md` for detailed security architecture.

## Build System Architecture

```
Host System
├── Podman Container (Ansible Vault Decryption)
│   └── Decrypts live-image-vault.yml
│
└── Podman Container (KIWI Build - Privileged)
    ├── Installs KIWI + dependencies
    ├── Builds image root filesystem
    ├── Injects credentials
    ├── Runs config.sh (creates user, configures SSH)
    ├── Creates UEFI boot images
    └── Generates bootable ISO
```

**Workflow:**
1. Load configuration (`live-image.conf`)
2. Decrypt vault if present (`live-image-vault.yml`)
3. Merge and inject credentials
4. Build ISO in isolated container
5. Clean up temporary files
6. Output ISO to `outdir/`

## Contributing

This is a customization of the upstream CentOS SIG Alt Images project for automation use cases.

**Submitting improvements:**
- Build system enhancements welcome
- Documentation improvements welcome
- Security hardening suggestions welcome

**Upstream changes:**
- For KIWI description changes, see `UPSTREAM-SYNC.md`
- Customizations in this repo don't go upstream

## Support and Resources

- **Build issues:** See Troubleshooting section above
- **Upstream KIWI:** https://pagure.io/centos-sig-alt-images/kiwi-descriptions
- **KIWI documentation:** https://osinside.github.io/kiwi/
- **Project issues:** https://github.com/heatmiser/centos-stream-ansible-iso/issues

## License

GNU General Public License v3.0

Inherits license from upstream CentOS SIG Alt Images project.

See `LICENSE` and `ATTRIBUTION.md` for details.
