#!/bin/bash
#
# Chroot Setup Script - Part 1
# Sets up the base system for ARM64 Rescuezilla build
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

echo "Starting chroot setup part 1 for ARM64..."

# Update package lists
apt-get update

# Set timezone to avoid prompts
echo "tzdata tzdata/Areas select Etc" | debconf-set-selections
echo "tzdata tzdata/Zones/Etc select UTC" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata

# Set locale to avoid prompts  
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y locales
locale-gen en_US.UTF-8
echo 'LANG="en_US.UTF-8"' > /etc/default/locale

# Install essential packages for ARM64 live system
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ubuntu-minimal \
    ubuntu-standard \
    casper \
    lupin-casper \
    discover \
    laptop-detect \
    os-prober \
    network-manager \
    resolvconf \
    net-tools \
    wireless-tools \
    wpagui \
    locales \
    grub-common \
    grub2-common \
    grub-efi-arm64 \
    grub-efi-arm64-bin \
    linux-generic \
    initramfs-tools \
    squashfs-tools \
    genisoimage \
    memtest86+ || echo "memtest86+ not available for ARM64"

# Install desktop environment optimized for ARM64
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ubuntu-desktop-minimal \
    lightdm \
    lightdm-gtk-greeter

# Install additional packages needed for Rescuezilla on ARM64
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-pip \
    python3-tk \
    python3-dev \
    gir1.2-gtk-3.0 \
    gir1.2-glib-2.0 \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gdkpixbuf-2.0 \
    python3-requests \
    python3-babel \
    gparted \
    fsarchiver \
    partimage \
    testdisk \
    ddrescue \
    gddrescue \
    safecopy \
    hdparm \
    smartmontools \
    sysstat \
    pv \
    lshw \
    dmidecode \
    hwinfo \
    cpuid || echo "cpuid not available for ARM64" \
    lscpu \
    util-linux \
    ntfs-3g \
    dosfstools \
    mtools \
    hfsutils \
    hfsprogs \
    jfsutils \
    nilfs-tools \
    reiser4progs \
    reiserfsprogs \
    udftools \
    xfsprogs \
    btrfs-progs \
    f2fs-tools \
    exfat-fuse \
    exfat-utils \
    cryptsetup \
    lvm2 \
    mdadm \
    openssh-client \
    wget \
    curl \
    rsync \
    pixz \
    pbzip2 \
    lz4 \
    zstd \
    file \
    vim \
    nano \
    less \
    tree \
    htop \
    iotop \
    nethogs \
    tcpdump \
    ethtool \
    bridge-utils \
    vlan

# Clean up
apt-get autoremove -y
apt-get autoclean

echo "Chroot setup part 1 completed for ARM64"