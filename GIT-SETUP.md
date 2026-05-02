# Git Repository Setup Guide

This guide walks you through initializing this directory as a git repository and pushing to GitHub.

## Prerequisites

- Git installed on your RHEL system
- GitHub account
- SSH key configured for GitHub (or HTTPS credentials)

## Step 1: Initialize Git Repository

```bash
# In the project root directory
git init

# Verify .gitignore is in place
cat .gitignore
```

The `.gitignore` file protects sensitive data:
- `live-image.conf` - May contain sensitive paths
- `live-image-vault.yml` - Encrypted credentials
- `keys/` - SSH keys
- `outdir/` - Build artifacts
- Temporary credential files

## Step 2: Create Initial Commit

```bash
# Add all files (respecting .gitignore)
git add .

# Verify what will be committed
git status

# Review files to be committed
git diff --cached --name-only

# Ensure these are NOT staged:
# - live-image.conf (only .example should be staged)
# - live-image-vault.yml (only .example should be staged)
# - keys/ directory
# - outdir/ directory
# - kiwi-descriptions/root/etc/liveimage-credentials.conf

# Create initial commit
git commit -m "Initial commit: CentOS Stream 10 MIN-Live ISO builder

- Portable containerized build system for Ansible automation
- Based on CentOS SIG Alt Images kiwi-descriptions (c10s branch)
- Includes SSH server, Python3, configurable user with sudo
- Ansible Vault integration for credential management
- Works on Linux/Mac/Windows with only Podman required

Features:
- Custom user configuration with SSH key/password auth
- Passwordless sudo for automation
- Full documentation and examples
- Proper GPL-3.0 licensing and attribution

See README.md for quick start and documentation."
```

## Step 3: Create GitHub Repository

**Option A: Via GitHub Web Interface**

1. Go to https://github.com/new
2. Repository name: `centos-stream-ansible-iso`
3. Description: "Portable CentOS Stream live ISO builder for bare metal Ansible automation. Currently supports CentOS Stream 10."
4. Public or Private: Choose based on your needs
5. **Do NOT initialize with README, .gitignore, or license** (we already have these)
6. Click "Create repository"

**Option B: Via GitHub CLI**

```bash
# Install gh CLI if not present
sudo dnf install gh

# Authenticate
gh auth login

# Create repository
gh repo create centos-stream-ansible-iso --public \
  --description "Portable CentOS Stream live ISO builder for bare metal Ansible automation" \
  --source=. \
  --remote=origin

# Skip to Step 5 (gh creates remote automatically)
```

## Step 4: Add GitHub Remote

Replace `YOUR_USERNAME` with your GitHub username:

```bash
# SSH (recommended)
git remote add origin git@github.com:YOUR_USERNAME/centos-stream-ansible-iso.git

# Or HTTPS
git remote add origin https://github.com/YOUR_USERNAME/centos-stream-ansible-iso.git

# Verify
git remote -v
```

## Step 5: Push to GitHub

```bash
# Set default branch name (if needed)
git branch -M main

# Push initial commit
git push -u origin main

# Verify on GitHub
# Visit: https://github.com/YOUR_USERNAME/centos-stream-ansible-iso
```

## Step 6: Verify Repository

Check that GitHub shows:
- ✅ README.md displays on main page
- ✅ LICENSE file detected
- ✅ All documentation files present
- ✅ Example files present (.example suffix)
- ✅ No sensitive files (live-image.conf, keys/, etc.)

## Step 7: Create Initial Release (Optional)

```bash
# Tag the initial release
git tag -a v1.0.0 -m "Initial release

Features:
- Portable containerized ISO builder
- Configurable user with SSH/password auth
- Ansible Vault integration
- Complete documentation
- Based on CentOS SIG Alt Images c10s"

# Push tag
git push origin v1.0.0

# Or create release via GitHub web UI or gh CLI:
gh release create v1.0.0 \
  --title "v1.0.0 - Initial Release" \
  --notes "See README.md for documentation and quick start guide"
```

## Repository Configuration (Optional)

### Add Topics

On GitHub repository page, add topics:
- `centos-stream`
- `live-iso`
- `ansible`
- `automation`
- `kiwi`
- `bare-metal`
- `podman`

### Branch Protection (Recommended)

For `main` branch:
1. Go to Settings → Branches → Add rule
2. Branch name pattern: `main`
3. Enable:
   - ✅ Require pull request reviews before merging
   - ✅ Require status checks to pass (if using CI/CD)
   - ✅ Include administrators (optional)

### Add Repository Description

Settings → General → Description:
```
Portable CentOS Stream live ISO builder for bare metal Ansible automation. Currently supports Stream 10. Includes SSH, Python3, configurable users, and Ansible Vault integration. Requires only Podman.
```

### Add Website

Settings → General → Website:
```
https://sigs.centos.org/altimages/
```

## Ongoing Workflow

### Making Changes

```bash
# Create feature branch (recommended)
git checkout -b feature/description

# Make changes
vi some-file.md

# Commit
git add some-file.md
git commit -m "Brief description of change"

# Push
git push -u origin feature/description

# Create pull request on GitHub (if using branch protection)
# Or merge to main directly (if not using protection)
```

### Direct Commits to Main

```bash
# Make changes
vi some-file.md

# Commit
git add some-file.md
git commit -m "Update documentation"

# Push
git push
```

## Important Reminders

### Never Commit Sensitive Files

Always verify before pushing:

```bash
# Check what's staged
git status

# Check for sensitive content
git diff --cached | grep -i "password\|key\|secret"

# If you accidentally staged sensitive files:
git reset HEAD <file>
```

### If You Accidentally Commit Secrets

```bash
# If not yet pushed:
git reset HEAD~1  # Undo last commit, keep changes

# If already pushed (DANGEROUS - rewrites history):
git reset HEAD~1
git push --force

# Better: Rotate the compromised credentials immediately!
```

### Protect Your Vault Password

Never commit:
- `.vault_pass` files
- Unencrypted `live-image-vault.yml`
- Decrypted credentials in any form

## Sharing and Collaboration

### Cloning on Another System

```bash
git clone https://github.com/YOUR_USERNAME/centos-stream-ansible-iso.git
cd centos-stream-ansible-iso

# Create your local configuration
cp live-image.conf.example live-image.conf
# Edit as needed

# If using vault:
# Copy your encrypted vault or create new one
```

### Contributing (For Collaborators)

1. Fork the repository (or work on branches if direct access)
2. Create feature branch
3. Make changes
4. Test build process
5. Submit pull request
6. Reference any related issues

## CI/CD Integration (Future)

Consider adding GitHub Actions for:
- Automated syntax checking
- Build testing (requires privileged containers)
- Documentation linting
- Release automation

Example workflow location: `.github/workflows/build-test.yml`

## Questions?

See:
- README.md for general usage
- CLAUDE.md for development guide
- UPSTREAM-SYNC.md for syncing with upstream

Or open an issue on GitHub.
