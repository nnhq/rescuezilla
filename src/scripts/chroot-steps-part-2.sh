#!/bin/bash
#
# Chroot Setup Script - Part 2  
# Configures the system for ARM64 Rescuezilla
#
# Copyright (C) 2019-2024 Rescuezilla Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

set -x
# Exit on any error
set -e

echo "Starting chroot setup part 2 for ARM64..."

# Create live user
adduser --disabled-password --gecos "Live User" live
echo "live:live" | chpasswd
usermod -aG sudo live

# Configure autologin for live session
mkdir -p /etc/lightdm/lightdm.conf.d/
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf <<EOF
[Seat:*]
autologin-user=live
autologin-user-timeout=0
EOF

# Set hostname for ARM64 system
echo "rescuezilla-arm64" > /etc/hostname

# Update /etc/hosts
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   rescuezilla-arm64

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Configure network interfaces
cat > /etc/NetworkManager/NetworkManager.conf <<EOF
[main]
plugins=ifupdown,keyfile
dns=dnsmasq

[ifupdown]
managed=false

[device]
wifi.scan-rand-mac-address=no
EOF

# Install Python dependencies for Rescuezilla
pip3 install --upgrade pip
pip3 install setuptools wheel

# Create desktop entry for Rescuezilla
mkdir -p /home/live/Desktop
cat > /home/live/Desktop/rescuezilla.desktop <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Rescuezilla
Comment=The Swiss Army Knife of System Recovery
Exec=python3 /usr/share/rescuezilla/rescuezilla.py
Icon=/usr/share/rescuezilla/rescuezilla.png
Terminal=false
Categories=System;
EOF

chmod +x /home/live/Desktop/rescuezilla.desktop
chown live:live /home/live/Desktop/rescuezilla.desktop

# Create autostart entry
mkdir -p /home/live/.config/autostart
cp /home/live/Desktop/rescuezilla.desktop /home/live/.config/autostart/
chown -R live:live /home/live/.config

# Configure GRUB for ARM64 EFI
echo 'GRUB_DEFAULT=0' >> /etc/default/grub
echo 'GRUB_TIMEOUT=10' >> /etc/default/grub
echo 'GRUB_DISTRIBUTOR="Rescuezilla ARM64"' >> /etc/default/grub
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> /etc/default/grub
echo 'GRUB_CMDLINE_LINUX=""' >> /etc/default/grub

# Update initramfs for ARM64
update-initramfs -u

# Set up casper configuration for live boot
mkdir -p /etc/casper
echo "export USERNAME=live" > /etc/casper.conf
echo "export USERFULLNAME=\"Live User\"" >> /etc/casper.conf
echo "export HOST=rescuezilla-arm64" >> /etc/casper.conf

# Create manifest files
dpkg-query -W --showformat='${Package} ${Version}\n' > /var/lib/dpkg/info/live-system.list

# Configure systemd for live system
systemctl enable NetworkManager
systemctl enable lightdm

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*

# Remove machine-id to allow it to be regenerated on first boot
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id

echo "Chroot setup part 2 completed for ARM64"