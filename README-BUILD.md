# Building Custom CentOS Stream 10 MIN-Live ISO

This guide explains how to build a customized CentOS Stream 10 text-only live ISO designed for bare metal automation with Ansible.

## Features

- **Text-only live environment** - Minimal footprint, fast boot
- **SSH server enabled** - Remote access from boot
- **Python3 included** - Ready for Ansible automation
- **Configurable user** - Custom username, SSH key, and password
- **Passwordless sudo** - Full root access for automation
- **Portable build process** - Works on any system with Podman
- **Ansible Vault integration** - Secure credential management

## Prerequisites

- **Podman** installed and running
  - Linux: `dnf install podman` or `apt install podman`
  - Mac: Install [Podman Desktop](https://podman.io/getting-started/installation)
  - Windows: Install Podman in WSL2

That's it! No other dependencies required.

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd centos-sig-alt-images
```

### 2. Create Configuration

```bash
# Copy example configuration
cp live-image.conf.example live-image.conf

# Edit configuration
vi live-image.conf
```

Minimal configuration:
```bash
LIVE_USERNAME="ansible"
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"
```

### 3. Generate SSH Key (if needed)

```bash
mkdir -p keys
ssh-keygen -t ed25519 -f keys/automation -N "" -C "automation@liveiso"
```

### 4. Build ISO

```bash
./build-live-image.sh
```

The build process will:
- Pull required container images
- Install kiwi-ng in a CentOS Stream 10 container
- Build the ISO (takes 15-30 minutes)
- Output ISO to `./outdir/`

### 5. Test the ISO

```bash
# Boot in QEMU
qemu-system-x86_64 -m 2048 -cdrom outdir/*.iso -boot d \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0

# SSH to the live system (from another terminal)
ssh -i keys/automation -p 2222 ansible@localhost
```

## Configuration Options

### Plaintext Configuration (live-image.conf)

```bash
# Username for automation account
LIVE_USERNAME="ansible"

# SSH public key file
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"

# Additional groups (comma-separated)
LIVE_USER_GROUPS="wheel,docker"

# Password hash (optional, better to use vault)
LIVE_USER_PASSWORD_HASH="$6$..."
```

### Encrypted Credentials (live-image-vault.yml)

For sensitive data like password hashes:

**Create and encrypt vault:**

```bash
# Copy example
cp live-image-vault.yml.example live-image-vault.yml

# Generate password hash
openssl passwd -6 'YourPassword123'

# Edit vault file with your data
vi live-image-vault.yml

# Encrypt with ansible-vault
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
# View vault
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

Most secure option:

```bash
# live-image.conf
LIVE_USERNAME="ansible"
LIVE_USER_SSHKEY_FILE="./keys/automation.pub"
```

### Password Only

Simpler for testing:

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

## Testing and Verification

### Boot Test

```bash
# Start VM with ISO
qemu-system-x86_64 -m 2048 \
  -cdrom outdir/CentOS-Stream-Alternative-Images.x86_64-*.iso \
  -boot d \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0
```

### Console Verification

The system should autologin as your configured user. Verify:

```bash
# Check username
whoami  # Should show your LIVE_USERNAME

# Check SSH service
systemctl status sshd  # Should be active (running)

# Check Python
python3 --version  # Should show Python 3.x

# Check sudo
sudo -l  # Should show NOPASSWD: ALL

# Test sudo
sudo whoami  # Should show 'root' without password prompt

# Check network
ip addr  # Should have network interface
```

### SSH Access Test

```bash
# From build host
ssh -i keys/automation -p 2222 ansible@localhost

# Test sudo over SSH
ssh -i keys/automation -p 2222 ansible@localhost 'sudo whoami'
```

### Ansible Test

```bash
# Create inventory
cat > test-inventory.yml <<EOF
all:
  hosts:
    liveiso:
      ansible_host: localhost
      ansible_port: 2222
      ansible_user: ansible
      ansible_ssh_private_key_file: ./keys/automation
EOF

# Test connectivity
ansible -i test-inventory.yml liveiso -m ansible.builtin.ping

# Test privileged access
ansible -i test-inventory.yml liveiso -m ansible.builtin.command \
  -a "whoami" --become

# Run playbook
cat > test-playbook.yml <<EOF
---
- name: Test live ISO
  hosts: liveiso
  become: true
  tasks:
    - name: Check OS
      ansible.builtin.debug:
        msg: "Running on {{ ansible_distribution }} {{ ansible_distribution_version }}"

    - name: Verify Python
      ansible.builtin.command: python3 --version
      register: python_version

    - name: Show result
      ansible.builtin.debug:
        var: python_version.stdout
EOF

ansible-playbook -i test-inventory.yml test-playbook.yml
```

## Platform-Specific Notes

### Linux

Native Podman support. Full functionality including privileged containers.

```bash
# Install Podman
sudo dnf install podman    # Fedora/RHEL/CentOS
sudo apt install podman    # Debian/Ubuntu
```

### macOS

Requires Podman Machine (virtual machine backend).

```bash
# Install Podman Desktop or via Homebrew
brew install podman

# Initialize Podman machine
podman machine init
podman machine start

# Build normally
./build-live-image.sh
```

### Windows (WSL2)

Install Podman inside WSL2 (Ubuntu/Fedora).

```bash
# In WSL2 terminal
sudo apt install podman    # Ubuntu
# or
sudo dnf install podman    # Fedora

# Build normally
./build-live-image.sh
```

## Troubleshooting

### Podman Connection Errors

```bash
# Check Podman status
podman ps

# On Mac: ensure Podman machine is running
podman machine list
podman machine start

# Check permissions
podman version
```

### Build Failures

```bash
# Check available disk space (build needs ~5GB)
df -h

# Check Podman storage
podman system df

# Clean up old images/containers
podman system prune -a
```

### Vault Decryption Errors

```bash
# Verify vault file is encrypted
file live-image-vault.yml

# Test decryption manually
podman run --rm -it -v $(pwd):/work:z \
  quay.io/ansible/creator-ee:latest \
  ansible-vault view /work/live-image-vault.yml
```

### SSH Connection Issues in VM

```bash
# Check network in VM
ip addr

# Check SSH service
systemctl status sshd

# Check firewall (should be disabled in live environment)
systemctl status firewalld

# Try password auth if key fails
ssh -o PreferredAuthentications=password -p 2222 ansible@localhost
```

## Advanced Usage

### Custom Packages

Edit `kiwi-descriptions/components/desktop-environments.xml`:

```xml
<packages type="image" patternType="plusRecommended" profiles="MIN-Desktop">
    <!-- Existing packages -->
    <package name="bash"/>
    <package name="openssh-server"/>
    <package name="python3"/>
    <package name="sudo"/>

    <!-- Add your packages here -->
    <package name="vim"/>
    <package name="tmux"/>
    <package name="git"/>
</packages>
```

### Multiple SSH Keys

Use vault file for additional keys:

```yaml
additional_ssh_keys:
  - "ssh-rsa AAAAB3... user1@host"
  - "ssh-ed25519 AAAAC3... user2@host"
  - "ssh-rsa AAAAB3... user3@host"
```

### Custom User Groups

```bash
# live-image.conf
LIVE_USER_GROUPS="wheel,docker,libvirt,kvm"
```

## Security Considerations

1. **SSH Keys**: Use ed25519 keys for better security
2. **Passwords**: Always use strong passwords and Ansible Vault
3. **Vault Files**: Never commit encrypted vaults with real credentials
4. **Credentials File**: Added to .gitignore automatically, never commit
5. **Build Artifacts**: Clean up `outdir/` before committing changes

## File Structure

```
.
├── build-live-image.sh              # Main build script
├── live-image.conf                  # Your configuration (git-ignored)
├── live-image.conf.example          # Configuration template
├── live-image-vault.yml             # Your vault (git-ignored)
├── live-image-vault.yml.example     # Vault template
├── README-BUILD.md                  # This file
├── kiwi-descriptions/               # KIWI image description
│   ├── config.sh                    # Modified for custom user
│   ├── components/
│   │   └── desktop-environments.xml # Modified for packages
│   └── root/                        # Overlay files
│       └── etc/
│           └── liveimage-credentials.conf  # Generated (temporary)
├── outdir/                          # Build output (git-ignored)
│   └── *.iso                        # Generated ISO
└── keys/                            # SSH keys (git-ignored)
    ├── automation
    └── automation.pub
```

## Contributing

This is a local customization based on the upstream CentOS SIG Alt Images project. We do not submit PRs upstream. To sync with upstream:

```bash
cd kiwi-descriptions
git fetch origin
git merge origin/c10s
# Resolve conflicts, preserving our customizations
```

## License

This project inherits the GPL-3.0 license from the upstream CentOS SIG Alt Images project.

## Support

For issues with:
- **Upstream KIWI descriptions**: https://pagure.io/centos-sig-alt-images/kiwi-descriptions
- **KIWI NG tool**: https://osinside.github.io/kiwi/
- **This customization**: Open an issue in this repository
