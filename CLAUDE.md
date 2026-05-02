# CentOS Stream 10 MIN-Live ISO Builder

## Project Overview

This project creates customized CentOS Stream 10 text-only live ISOs for bare metal automation with Ansible. Built on top of the upstream CentOS SIG Alt Images project with local customizations for automation workflows.

## Purpose

Generate bootable live ISOs with:
- SSH server enabled from boot
- Python3 for Ansible automation
- Configurable user with SSH key/password authentication
- Passwordless sudo access
- Fully containerized, portable build process

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

2. `kiwi-descriptions/components/desktop-environments.xml` (lines 71-75)
   - Added packages to MIN-Desktop profile:
     - openssh-server
     - python3
     - sudo

### Build Process

**Container-Native Architecture:**
- **Ansible Container** (`quay.io/ansible/creator-ee:latest`) - Decrypts Ansible Vault
- **CentOS Stream 10 Container** (`quay.io/centos/centos:stream10-development`) - Runs kiwi-ng build

**Workflow:**
1. Load `live-image.conf` (plaintext config)
2. Decrypt `live-image-vault.yml` (if exists) using Ansible container
3. Merge configuration and create credential injection file
4. Run kiwi-ng build in CentOS Stream 10 container
5. Clean up temporary credential files
6. Output ISO to `outdir/`

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

- **Credentials at rest**: Encrypted with Ansible Vault
- **Credentials in transit**: Injected as temporary file, deleted after build
- **SSH authentication**: Key-based preferred, password fallback supported
- **Sudo access**: Passwordless for wheel group (automation requirement)

### Files Never to Commit

- `live-image.conf` (may contain non-sensitive config, but user-specific)
- `live-image-vault.yml` (encrypted credentials)
- `kiwi-descriptions/root/etc/liveimage-credentials.conf` (temporary)
- `outdir/*` (build artifacts)
- `keys/*` (SSH keys)

All protected by `.gitignore`.

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
- ISO boot verification
- SSH access testing
- Ansible connectivity testing

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
