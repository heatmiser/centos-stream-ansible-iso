# Upstream Sync Workflow

This document provides an opinionated workflow for maintaining our customizations while staying synchronized with upstream CentOS SIG Alt Images changes.

## Overview

We track the upstream `kiwi-descriptions` files directly in our repository with local modifications. This approach provides:
- Complete control over customizations
- Simple repository structure
- Easy deployment and use

**Trade-off**: Manual sync process when upstream updates are needed.

## Modified Files to Protect

These files contain our customizations and must be preserved during upstream sync:

1. **kiwi-descriptions/config.sh**
   - Lines 147-218: MIN-Live customizations
   - Search markers: `# Load custom credentials`, `LIVE_USERNAME`, `sshd.service`

2. **kiwi-descriptions/components/desktop-environments.xml**
   - Lines 71-76: MIN-Desktop package additions
   - Search markers: `openssh-server`, `python3`, `sudo` (in MIN-Desktop section)

## Sync Workflow

### When to Sync

Consider syncing with upstream when:
- New CentOS Stream 10 release or updates
- Security updates in upstream KIWI descriptions
- Bug fixes or improvements in upstream
- New features you want to incorporate

**Check for updates**: Visit https://pagure.io/centos-sig-alt-images/kiwi-descriptions/commits/c10s

### Preparation

Before syncing, ensure you have:
1. Clean working directory (commit or stash local changes)
2. Current build tested and working
3. Backup of current state (git tag recommended)

```bash
# Tag current state
git tag -a v$(date +%Y%m%d)-pre-sync -m "State before upstream sync"
git push --tags

# Verify clean state
git status
```

### Sync Process

**Option A: Manual File Comparison (Recommended)**

This gives you full control and visibility into changes:

```bash
# 1. Create temporary directory for upstream
mkdir -p /tmp/upstream-kiwi
cd /tmp/upstream-kiwi

# 2. Clone fresh upstream
git clone https://pagure.io/centos-sig-alt-images/kiwi-descriptions.git
cd kiwi-descriptions
git checkout c10s

# 3. Compare files (from your project root)
cd /path/to/your/centos-sig-alt-images

# Compare all files
diff -ur /tmp/upstream-kiwi/kiwi-descriptions kiwi-descriptions/ \
  | grep -v "^Only in" \
  | tee upstream-diff.txt

# 4. Review differences
less upstream-diff.txt

# 5. Selectively apply upstream changes
# For each modified file, manually review and merge changes
# PRESERVING our customizations in config.sh and desktop-environments.xml

# Example for config.sh:
vimdiff kiwi-descriptions/config.sh /tmp/upstream-kiwi/kiwi-descriptions/config.sh
# Or use your preferred merge tool:
# meld kiwi-descriptions/config.sh /tmp/upstream-kiwi/kiwi-descriptions/config.sh

# For unmodified files, copy directly from upstream:
cp /tmp/upstream-kiwi/kiwi-descriptions/README.md kiwi-descriptions/

# 6. Cleanup
rm -rf /tmp/upstream-kiwi
rm upstream-diff.txt
```

**Option B: Patch-Based Workflow**

More structured, preserves modification history:

```bash
# 1. Save our modifications as patches (one-time setup)
# This creates patch files for our changes
cd kiwi-descriptions

# Create patch for config.sh changes
git diff --no-index config.sh.orig config.sh > ../patches/config-sh-customizations.patch
# (Requires keeping .orig files of upstream versions)

# Create patch for desktop-environments.xml changes  
git diff --no-index components/desktop-environments.xml.orig \
  components/desktop-environments.xml > ../patches/desktop-environments-customizations.patch

# 2. During sync, fetch upstream and reapply patches
# [Fetch upstream files as in Option A]

# 3. Copy upstream files
cp -r /tmp/upstream-kiwi/kiwi-descriptions/* kiwi-descriptions/

# 4. Reapply our patches
cd kiwi-descriptions
patch -p0 < ../patches/config-sh-customizations.patch
patch -p0 < ../patches/desktop-environments-customizations.patch

# 5. Resolve any conflicts manually
```

### Post-Sync Verification

After syncing, always verify:

```bash
# 1. Check syntax
# Our modifications should still be present:
grep -n "LIVE_USERNAME" kiwi-descriptions/config.sh
grep -n "openssh-server" kiwi-descriptions/components/desktop-environments.xml

# 2. Build test
./build-live-image.sh
# Verify build completes successfully

# 3. ISO test (if critical changes)
# Boot and verify customizations still work

# 4. Document sync
# Update ATTRIBUTION.md with new sync date and commit info
vi ATTRIBUTION.md

# 5. Commit
git add .
git commit -m "Sync with upstream c10s (date: $(date +%Y-%m-%d))

- Updated kiwi-descriptions from upstream
- Preserved customizations in config.sh and desktop-environments.xml
- Tested build: SUCCESS
- See ATTRIBUTION.md for upstream commit reference"

git push
```

### Tracking Upstream Changes

Keep a record of upstream state:

```bash
# Create tracking file
cat > UPSTREAM-STATE.md <<EOF
# Upstream Tracking

## Last Sync: $(date +%Y-%m-%d)

## Upstream Commit
Branch: c10s
Commit: [hash from upstream]
Date: [upstream commit date]

## Changes Applied
- [List significant upstream changes incorporated]

## Changes Skipped
- [List upstream changes intentionally not incorporated]

## Our Modifications Preserved
- config.sh: Lines 147-218 (user configuration)
- desktop-environments.xml: Lines 71-76 (package additions)
EOF
```

## Conflict Resolution

If upstream modifies the same sections we've customized:

### For config.sh MIN-Live Section

1. **Identify the conflict**: Upstream changed lines overlapping with our 147-218 range
2. **Understand upstream intent**: What are they trying to fix/add?
3. **Merge carefully**:
   - Preserve our credential loading logic
   - Integrate their bug fixes or improvements
   - Test thoroughly

### For desktop-environments.xml

1. **Check if MIN-Desktop profile changed**: Look for package additions/removals
2. **Merge package lists**: Add any new packages from upstream to our modified list
3. **Preserve our additions**: Ensure openssh-server, python3, sudo remain

## Emergency Rollback

If sync causes issues:

```bash
# Option 1: Rollback to pre-sync tag
git reset --hard v$(date +%Y%m%d)-pre-sync

# Option 2: Revert specific commit
git log  # Find sync commit hash
git revert <commit-hash>

# Option 3: Restore from backup
git checkout <previous-commit> -- kiwi-descriptions/
```

## Best Practices

1. **Sync frequency**: Every 3-6 months or when critical upstream updates occur
2. **Always test**: Build and boot test after every sync
3. **Document changes**: Update ATTRIBUTION.md and commit messages
4. **Tag before sync**: Makes rollback trivial
5. **Review carefully**: Upstream may change assumptions your modifications rely on
6. **Keep patches small**: Easier to reapply and merge

## Automated Sync Checking

Optional: Set up automated checks for upstream changes:

```bash
#!/bin/bash
# check-upstream.sh - Run monthly via cron

UPSTREAM="https://pagure.io/centos-sig-alt-images/kiwi-descriptions.git"
BRANCH="c10s"

# Fetch upstream
git ls-remote $UPSTREAM refs/heads/$BRANCH > /tmp/upstream-head.txt

# Compare with last known
if [ -f .last-upstream-commit ]; then
    if ! diff -q .last-upstream-commit /tmp/upstream-head.txt; then
        echo "ALERT: Upstream has new commits on $BRANCH"
        echo "Consider syncing: See UPSTREAM-SYNC.md"
    fi
fi

mv /tmp/upstream-head.txt .last-upstream-commit
```

## Questions?

For questions about the sync process, open an issue or review the commit history to see how previous syncs were handled.
