# Attribution and Upstream Sources

## Upstream Project

This project is based on and includes code from the **CentOS SIG Alt Images** project:

- **Project**: CentOS Stream Alternative Images - KIWI descriptions
- **Source**: https://pagure.io/centos-sig-alt-images/kiwi-descriptions
- **Branch**: c10s (CentOS Stream 10)
- **License**: GNU General Public License v3.0
- **Copyright**: CentOS Alternative Images SIG
- **Contact**: sig-altimages@centosproject.org

The `kiwi-descriptions/` directory contains files from the upstream project with local modifications for automation use cases.

## Upstream Snapshot Information

**Last synced**: May 2, 2026
**Upstream commit**: Latest from c10s branch as of sync date
**Source URL**: https://pagure.io/centos-sig-alt-images/kiwi-descriptions/tree/c10s

## Modified Files

The following files have been modified from upstream:

1. **kiwi-descriptions/config.sh** (lines 147-218)
   - Added credential loading from `/etc/liveimage-credentials.conf`
   - Replaced hardcoded 'liveuser' with configurable username
   - Added SSH key and password configuration
   - Added passwordless sudo configuration for wheel group
   - Enabled sshd service

2. **kiwi-descriptions/components/desktop-environments.xml** (lines 71-76)
   - Added packages to MIN-Desktop profile:
     - openssh-server
     - python3
     - sudo

3. **kiwi-descriptions/platforms/workstation.xml** (line 23)
   - Changed MIN-Live profile to MIN-Live-Automation
   - Changed dependency from LiveInstall to MinLiveBoot

## New Files Added

The following files are original to this project and not from upstream:

- `build-live-image.sh` - Containerized build wrapper
- `live-image.conf.example` - Configuration template
- `live-image-vault.yml.example` - Vault template
- `kiwi-descriptions/components/minlive-boot.xml` - Minimal live boot profile (no installer)
- `README-BUILD.md` - Build documentation
- `README.md` - Main project documentation
- `CLAUDE.md` - Architecture and development guide
- `ATTRIBUTION.md` - This file
- `UPSTREAM-SYNC.md` - Upstream sync workflow
- `GIT-SETUP.md` - Git repository setup guide
- `.gitignore` - Git ignore rules
- `LICENSE` - Copy of GPL-3.0 from upstream

## Copyright and License

This derivative work is licensed under the same license as the upstream project:

**GNU General Public License v3.0**

See the LICENSE file for the full license text.

### Copyright Notices

**Original Work (kiwi-descriptions/)**
- Copyright © CentOS Alternative Images SIG
- Licensed under GPL-3.0

**Modifications and Additional Files**
- Modifications to upstream files are licensed under GPL-3.0
- New files created for this project are licensed under GPL-3.0
- Contributors retain copyright to their contributions

## Acknowledgments

- **CentOS SIG Alt Images** team for creating and maintaining the upstream KIWI descriptions
- **KIWI NG** project (https://osinside.github.io/kiwi/) for the image building framework
- **CentOS Stream** project for the base operating system

## Contributing

This is a local customization of the upstream project for specific automation use cases. We do not submit pull requests upstream as these modifications are tailored to specific requirements.

To sync with upstream changes, see UPSTREAM-SYNC.md.

## Questions or Issues

For issues with:
- **Upstream KIWI descriptions**: https://pagure.io/centos-sig-alt-images/kiwi-descriptions/issues
- **This customization**: Open an issue in this repository
- **KIWI NG tool**: https://github.com/OSInside/kiwi
