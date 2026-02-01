#!/bin/bash
#
# Live CD Builder Script
# Rescuezilla: The Swiss Army Knife of System Recovery
#
# Copyright (C) 2019-2024 Rescuezilla Contributors
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -x
# Exit on any error
set -e

if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Instead run: 'make focal-arm64-uefi'"
   exit 1
fi

# If BASE_BUILD_DIRECTORY is not set, default to working directory
if [[ -z "${BASE_BUILD_DIRECTORY}" ]]; then
  # Default directory is the git repository root + build/
  BASE_BUILD_DIRECTORY=$(pwd)/build/
fi

# For ARM64, we only support 64-bit builds with UEFI
if [[ -z "${ARCH}" ]]; then
    echo "ERROR: ARCH environment variable must be set to 'arm64'"
    exit 1
fi

if [[ "${ARCH}" != "arm64" ]]; then
    echo "ERROR: Only ARM64 architecture is supported. Got: ${ARCH}"
    exit 1
fi

if [[ -z "${CODENAME}" ]]; then
    echo "ERROR: CODENAME environment variable must be set"
    exit 1
fi

if [[ "${UEFI_ENABLED}" != "true" ]]; then
    echo "ERROR: UEFI_ENABLED must be set to 'true' for ARM64 builds"
    exit 1
fi

# Set defaults for ARM64
DEST_DIR=${BASE_BUILD_DIRECTORY}
ARCH="arm64"
KERNEL_ARCH="arm64"

# Create the base directory to build the ISO image
mkdir -p "${DEST_DIR}"

cd "${DEST_DIR}"
BUILD_DIR="${DEST_DIR}"
CHROOT_DIR="${BUILD_DIR}chroot"
ISO_DIR="${BUILD_DIR}iso"
SQUASHFS_DIR="${ISO_DIR}/live"
EFI_DIR="${ISO_DIR}/boot/efi"

echo "Building Rescuezilla for ARM64 with UEFI boot support"
echo "Codename: $CODENAME"
echo "Architecture: $ARCH"
echo "Build directory: $BUILD_DIR"

# Remove any existing build
if mountpoint -q "${CHROOT_DIR}/proc/" ; then sudo umount "${CHROOT_DIR}/proc/" ; fi
if mountpoint -q "${CHROOT_DIR}/sys/" ; then sudo umount "${CHROOT_DIR}/sys/" ; fi
if mountpoint -q "${CHROOT_DIR}/dev/" ; then sudo umount "${CHROOT_DIR}/dev/" ; fi
if mountpoint -q "${CHROOT_DIR}/tmp/" ; then sudo umount "${CHROOT_DIR}/tmp/" ; fi
sudo rm -rf "${CHROOT_DIR}" "${ISO_DIR}"

# Download Ubuntu base system for ARM64
sudo debootstrap --arch=${ARCH} ${CODENAME} "${CHROOT_DIR}" http://ports.ubuntu.com/ubuntu-ports/

# Copy qemu-user-static for emulation if running on x86_64
if [[ $(uname -m) == "x86_64" ]]; then
    sudo cp /usr/bin/qemu-aarch64-static "${CHROOT_DIR}/usr/bin/"
fi

# Set up chroot environment
echo "Setting up chroot environment for ARM64"
sudo mount --bind /dev "${CHROOT_DIR}/dev"
sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
sudo mount --bind /proc "${CHROOT_DIR}/proc"
sudo mount --bind /sys "${CHROOT_DIR}/sys"
sudo mount --bind /tmp "${CHROOT_DIR}/tmp"

# Create sources.list for ARM64
sudo tee "${CHROOT_DIR}/etc/apt/sources.list" > /dev/null <<EOF
deb http://ports.ubuntu.com/ubuntu-ports/ ${CODENAME} main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${CODENAME}-updates main restricted universe multiverse  
deb http://ports.ubuntu.com/ubuntu-ports/ ${CODENAME}-security main restricted universe multiverse
EOF

# DNS resolution inside chroot
sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

# Set environment variables for chroot
export CODENAME
export ARCH
export UEFI_ENABLED="true"

# Run the first part of chroot setup
sudo -E chroot "${CHROOT_DIR}" /bin/bash < ../src/scripts/chroot-steps-part-1.sh

# Copy Rescuezilla source into chroot
echo "Copying Rescuezilla source code into chroot"
sudo cp -r ../src/livecd/chroot/* "${CHROOT_DIR}/"

# Copy compiled binaries for ARM64
echo "Copying compiled ARM64 binaries"
sudo mkdir -p "${CHROOT_DIR}/usr/bin/"
sudo cp "${BUILD_DIR}/../sfdisk.v2.20.1.arm64" "${CHROOT_DIR}/usr/bin/sfdisk.v2.20.1"
sudo cp "${BUILD_DIR}/../partclone.restore.v0.2.43.arm64" "${CHROOT_DIR}/usr/bin/partclone.restore.v0.2.43"

# Copy partclone-latest ARM64 binaries
if [[ -d "${BUILD_DIR}/../partclone-latest-arm64/" ]]; then
    sudo cp -r "${BUILD_DIR}/../partclone-latest-arm64/"* "${CHROOT_DIR}/usr/bin/"
fi

# Copy partclone-utils ARM64 binaries  
if [[ -d "${BUILD_DIR}/../partclone-utils-arm64/" ]]; then
    sudo cp -r "${BUILD_DIR}/../partclone-utils-arm64/"* "${CHROOT_DIR}/usr/bin/"
fi

# Copy partclone-nbd ARM64 binaries
if [[ -d "${BUILD_DIR}/../partclone-nbd-arm64/" ]]; then
    sudo cp -r "${BUILD_DIR}/../partclone-nbd-arm64/"* "${CHROOT_DIR}/usr/bin/"
fi

# Run the second part of chroot setup  
sudo -E chroot "${CHROOT_DIR}" /bin/bash < ../src/scripts/chroot-steps-part-2.sh

# Remove qemu emulator if it was added
if [[ $(uname -m) == "x86_64" ]]; then
    sudo rm -f "${CHROOT_DIR}/usr/bin/qemu-aarch64-static"
fi

# Clean up chroot
echo "Cleaning up chroot environment"
sudo chroot "${CHROOT_DIR}" apt-get clean
sudo chroot "${CHROOT_DIR}" apt-get autoremove -y

# Unmount everything
sudo umount "${CHROOT_DIR}/tmp"
sudo umount "${CHROOT_DIR}/sys" 
sudo umount "${CHROOT_DIR}/proc"
sudo umount "${CHROOT_DIR}/dev/pts"
sudo umount "${CHROOT_DIR}/dev"

# Create the ISO filesystem structure
echo "Creating ISO filesystem structure for ARM64 UEFI"
mkdir -p "${ISO_DIR}"
mkdir -p "${SQUASHFS_DIR}"
mkdir -p "${EFI_DIR}/boot"

# Install GRUB for ARM64-EFI
echo "Installing GRUB for ARM64-EFI"
sudo grub-install --target=arm64-efi --efi-directory="${EFI_DIR}" --boot-directory="${ISO_DIR}/boot" --removable --recheck

# Create GRUB configuration for ARM64
sudo tee "${ISO_DIR}/boot/grub/grub.cfg" > /dev/null <<EOF
set default="0"
set timeout=10

menuentry "Rescuezilla ARM64" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Rescuezilla ARM64 (Safe Graphics)" {
    linux /live/vmlinuz boot=live components quiet splash nomodeset
    initrd /live/initrd.img  
}
EOF

# Copy the kernel and initrd for ARM64
echo "Copying ARM64 kernel and initrd"
sudo cp "${CHROOT_DIR}/boot/vmlinuz-"* "${SQUASHFS_DIR}/vmlinuz"
sudo cp "${CHROOT_DIR}/boot/initrd.img-"* "${SQUASHFS_DIR}/initrd.img"

# Create the squashfs filesystem
echo "Creating squashfs filesystem"
sudo mksquashfs "${CHROOT_DIR}" "${SQUASHFS_DIR}/filesystem.squashfs" -comp xz

# Create the ISO image for ARM64 UEFI
echo "Creating ARM64 UEFI-bootable ISO image"
cd "${BUILD_DIR}"
sudo xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "RESCUEZILLA_ARM64" \
    -eltorito-alt-boot \
    -e boot/efi/EFI/BOOT/BOOTAA64.EFI \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -output "rescuezilla.${ARCH}.${CODENAME}.iso" \
    "${ISO_DIR}"

echo ""
echo "ARM64 UEFI ISO image created successfully: rescuezilla.${ARCH}.${CODENAME}.iso"
ls -la "rescuezilla.${ARCH}.${CODENAME}.iso"