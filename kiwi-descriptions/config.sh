#!/bin/bash

set -euxo pipefail

#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]-[$kiwi_profiles]..."

#======================================
# Enable CRB repo by default
#--------------------------------------
dnf --assumeyes config-manager --set-enabled crb

#======================================
# Set SELinux booleans
#--------------------------------------
if [[ "$kiwi_profiles" != *"WSL"* ]]; then
	## Fixes KDE Plasma, see rhbz#2058657
	setsebool -P selinuxuser_execmod 1
fi

#======================================
# Clear machine specific configuration
#--------------------------------------
## Force generic hostname
echo "localhost" > /etc/hostname
## Clear machine-id on pre generated images
truncate -s 0 /etc/machine-id

#======================================
# Configure grub correctly
#--------------------------------------
if [[ "$kiwi_profiles" != *"Container"* ]] && [[ "$kiwi_profiles" != *"WSL"* ]]; then
	## Works around issues with grub-bls
	## See: https://github.com/OSInside/kiwi/issues/2198
	echo "GRUB_DEFAULT=saved" >> /etc/default/grub
	## Enable chrony
	systemctl enable chronyd.service
	## Enable oomd
	systemctl enable systemd-oomd.service
	## Enable resolved
	systemctl enable systemd-resolved.service
	## Enable persistent journal
	mkdir -p /var/log/journal
fi
#======================================
# Delete & lock the root user password
#--------------------------------------
if [[ "$kiwi_profiles" == *"AWS"* ]] || [[ "$kiwi_profiles" == *"Azure"* ]] || [[ "$kiwi_profiles" == *"OpenStack"* ]] || [[ "$kiwi_profiles" == *"Live"* ]] || [[ "$kiwi_profiles" == *"WSL"* ]]; then
	passwd -d root
	passwd -l root
fi

#======================================
# Setup default services
#--------------------------------------

if [[ "$kiwi_profiles" == *"AWS"* ]] || [[ "$kiwi_profiles" == *"Azure"* ]] || [[ "$kiwi_profiles" == *"OpenStack"* ]]; then
	## Enable cloud-init
	systemctl enable cloud-config.service cloud-final.service cloud-init.service cloud-init-local.service cloud-init.target
fi

if [[ "$kiwi_profiles" == *"Azure"* ]]; then
	## Enable Azure service
	systemctl enable waagent.service
fi

if [[ "$kiwi_profiles" == *"Live"* ]]; then
	## Enable livesys services
	systemctl enable livesys.service livesys-late.service
	if [[ "$kiwi_profiles" == *"CINNAMON"* ]]; then
		echo 'livesys_session="cinnamon"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"GNOME"* ]]; then
		echo 'livesys_session="gnome"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"KDE"* ]]; then
		echo 'livesys_session="kde"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"MATE"* ]]; then
		echo 'livesys_session="mate"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"MAX"* ]]; then
		echo 'livesys_session="max"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"MIN-Live"* ]]; then
		echo 'livesys_session="min"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"XFCE"* ]]; then
		echo 'livesys_session="xfce"' > /etc/sysconfig/livesys
	fi
	# anaconda-live icon is not being found.
	sed -i "s/org.fedoraproject.AnacondaInstaller/anaconda/" /usr/share/applications/liveinst.desktop

fi

#======================================
# Setup default target
#--------------------------------------
if [[ "$kiwi_profiles" == *"Live"* ]] && ! [[ "$kiwi_profiles" == *"MIN-Live"* ]] ; then
	systemctl set-default graphical.target
else
	systemctl set-default multi-user.target
fi

#======================================
# There is no setup for MAX, create our own
#--------------------------------------
if [[ "$kiwi_profiles" == *"MAX"* ]]; then
cat > /usr/libexec/livesys/sessions.d/livesys-max << MAX_EOF
#!/bin/sh
#
# live-max: max specific setup for livesys
# SPDX-License-Identifier: GPL-3.0-or-later
#

# show liveinst.desktop on desktop and in menu
sed -i 's/NoDisplay=true/NoDisplay=false/' /usr/share/applications/liveinst.desktop
mkdir /home/liveuser/Desktop
cp -a /usr/share/applications/liveinst.desktop /home/liveuser/Desktop/
# and mark it as executable (security feature)
chmod +x /home/liveuser/Desktop/liveinst.desktop
# and set xfce-exe-checksum metadata to make the harddisk installer desktop icon trusted (#2172854)
LIVEINST_DESKTOP_CHECKSUM="\$(sha256sum /home/liveuser/Desktop/liveinst.desktop | awk '{print \$1}')"
sudo -u liveuser dbus-launch gio set -t string /home/liveuser/Desktop/liveinst.desktop metadata::xfce-exe-checksum \${LIVEINST_DESKTOP_CHECKSUM}

# no updater applet in live environment
rm -f /etc/xdg/autostart/org.mageia.dnfdragora-updater.desktop
MAX_EOF
chmod 755 /usr/libexec/livesys/sessions.d/livesys-max
# Cleanup duplicate gnome desktops
rm -f /usr/share/wayland-sessions/gnome*wayland.desktop
# Use plasma login
systemctl enable plasmalogin.service -f
fi

#======================================
# There is no setup for MIN, create our own
#--------------------------------------
if [[ "$kiwi_profiles" == *"MIN-Live"* ]]; then

# Load custom credentials if provided
if [ -f /etc/liveimage-credentials.conf ]; then
	source /etc/liveimage-credentials.conf
fi

# Set defaults
LIVE_USERNAME="${LIVE_USERNAME:-ansible}"
LIVE_USER_GROUPS="${LIVE_USER_GROUPS:-wheel}"

# Create user account
useradd -m -G "${LIVE_USER_GROUPS}" -s /bin/bash "${LIVE_USERNAME}"

# Set password if provided
if [ -n "${LIVE_USER_PASSWORD_HASH}" ]; then
	echo "${LIVE_USERNAME}:${LIVE_USER_PASSWORD_HASH}" | chpasswd -e
fi

# Configure SSH key if provided
if [ -n "${LIVE_USER_SSHKEY}" ]; then
	mkdir -p "/home/${LIVE_USERNAME}/.ssh"
	echo "${LIVE_USER_SSHKEY}" > "/home/${LIVE_USERNAME}/.ssh/authorized_keys"
	chmod 700 "/home/${LIVE_USERNAME}/.ssh"
	chmod 600 "/home/${LIVE_USERNAME}/.ssh/authorized_keys"
	chown -R "${LIVE_USERNAME}:${LIVE_USERNAME}" "/home/${LIVE_USERNAME}/.ssh"
fi

# Add additional SSH keys if provided
if [ -n "${LIVE_USER_ADDITIONAL_SSHKEYS}" ]; then
	mkdir -p "/home/${LIVE_USERNAME}/.ssh"
	echo "${LIVE_USER_ADDITIONAL_SSHKEYS}" >> "/home/${LIVE_USERNAME}/.ssh/authorized_keys"
	chmod 700 "/home/${LIVE_USERNAME}/.ssh"
	chmod 600 "/home/${LIVE_USERNAME}/.ssh/authorized_keys"
	chown -R "${LIVE_USERNAME}:${LIVE_USERNAME}" "/home/${LIVE_USERNAME}/.ssh"
fi

# Enable SSH service
systemctl enable sshd.service

# Configure passwordless sudo for wheel group
cat > /etc/sudoers.d/90-liveimage-user << SUDO_EOF
## Allow members of wheel group to execute any command without password
%wheel ALL=(ALL) NOPASSWD: ALL
SUDO_EOF
chmod 440 /etc/sudoers.d/90-liveimage-user

cat > /usr/libexec/livesys/sessions.d/livesys-min << MIN_EOF
#!/bin/sh
#
# live-min: min specific setup for livesys
# SPDX-License-Identifier: GPL-3.0-or-later
#

# no updater applet in live environment
rm -f /etc/xdg/autostart/org.mageia.dnfdragora-updater.desktop

# Create the install script for the user
echo "/usr/bin/liveinst --text" > /home/${LIVE_USERNAME}/install_to_hard_drive
# and mark it as executable (security feature)
chmod +x /home/${LIVE_USERNAME}/install_to_hard_drive

MIN_EOF
chmod 755 /usr/libexec/livesys/sessions.d/livesys-min
# Setup Autologin for custom user
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << MIN_LOGIN_EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin ${LIVE_USERNAME} %I \$TERM
MIN_LOGIN_EOF
chmod 755 /etc/systemd/system/getty@tty1.service.d/autologin.conf
# Cleanup Autologin after install
cat > /usr/share/anaconda/post-scripts/86-noauto.ks << FIXBOOT_EOF
%post

echo "Cleanup Autologin"
rm -rf /etc/systemd/system/getty@tty1.service.d

%end
FIXBOOT_EOF

fi

if [[ "$kiwi_profiles" == *"KDE"* ]]; then
    # Turn off user creation, network, and timezone setup in anaconda
    # This should be done by plasma-setup on first boot
echo "[User Interface]" >> /etc/anaconda/profile.d/centos.conf
echo "hidden_spokes =" >> /etc/anaconda/profile.d/centos.conf
echo "    NetworkSpoke" >> /etc/anaconda/profile.d/centos.conf
echo "    PasswordSpoke" >> /etc/anaconda/profile.d/centos.conf
echo "    UserSpoke" >> /etc/anaconda/profile.d/centos.conf
echo "hidden_webui_pages =" >> /etc/anaconda/profile.d/centos.conf
echo "    anaconda-screen-accounts" >> /etc/anaconda/profile.d/centos.conf
echo "    anaconda-screen-date-time" >> /etc/anaconda/profile.d/centos.conf

    # Need to turn on plasma-setup
systemctl enable plasma-setup.service
fi

if [[ "$kiwi_profiles" == *"WSL"* ]]; then
    # Without this systemd-firstboot attempts to prompt the user
    # and many jobs get stuck waiting for eternity.
    echo 'LC_MESSAGES=en_US.UTF-8' >>  /etc/locale.conf

    wsl-setup --name CentOSStream-10-Alt
fi

#======================================
# Misc fixes and tweeks
#--------------------------------------

exit 0
