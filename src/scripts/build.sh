#!/bin/bash

# Echo each command
set -x

# Flag to enable integration test mode [1]. Disabled by default.
#
# Images built with this flag include an SSH server, a simple netcat TCP query server,
# and other changes to support Rescuezilla's automated end-to-end integration test suite [1].
#
# The flag is very useful for development and debugging too.  The SSH server is handy, as is
# the lower compression ratio on the squashfs root filesystem (for faster builds during development).
#
# This flag is obviously never enabled in production builds, and users are able to easily
# audit that no SSH server or netcat TCP query server is ever installed.
#
# [1] See src/integration-test/README.md for more information.
#
IS_INTEGRATION_TEST="${IS_INTEGRATION_TEST=:false}"

# Set the default base operating system, using the Ubuntu release's shortened code name [1].
# [1] https://wiki.ubuntu.com/Releases
CODENAME="${CODENAME:-INVALID}"

# Sets CPU architecture using Ubuntu designation [1]
# [1] https://help.ubuntu.com/lts/installation-guide/armhf/ch02s01.html
ARCH="${ARCH:-INVALID}"

# One-higher than directory containing this build script
BASEDIR="$(git rev-parse --show-toplevel)"

RESCUEZILLA_ISO_FILENAME=rescuezilla.$ARCH.$CODENAME.iso
# The base build directory is "build/", unless overridden by an environment variable
BASE_BUILD_DIRECTORY=${BASE_BUILD_DIRECTORY:-build/${BASE_BUILD_DIRECTORY}}
BUILD_DIRECTORY=${BUILD_DIRECTORY:-${BASE_BUILD_DIRECTORY}/${CODENAME}.${ARCH}}
mkdir -p "$BUILD_DIRECTORY/chroot"
# Ensure the build directory is an absolute path
BUILD_DIRECTORY=$( readlink -f "$BUILD_DIRECTORY" )
PKG_CACHE_DIRECTORY=${PKG_CACHE_DIRECTORY:-pkg.cache}
# Use a recent version of debootstrap from git
DEBOOTSTRAP_SCRIPT_DIRECTORY=${BASEDIR}/src/third-party/debootstrap
DEBOOTSTRAP_CACHE_DIRECTORY=debootstrap.$CODENAME.$ARCH
APT_PKG_CACHE_DIRECTORY=var.cache.apt.archives.$CODENAME.$ARCH
APT_INDEX_CACHE_DIRECTORY=var.lib.apt.lists.$CODENAME.$ARCH

# If the current commit is not tagged, the version number from `git
# describe--tags` is X.Y.Z-abc-gGITSHA-dirty, where X.Y.Z is the previous tag,
# 'abc' is the number of commits since that tag, gGITSHA is the git sha
# prepended by a 'g', and -dirty is present if the working tree has been
# modified.
#
# Note: the --match is a glob, not a regex.
VERSION_STRING=$(git describe --tags --match="[0-9].[0-9]*" --dirty)

# Date of current git commit in colon-less ISO 8601 format (2013-04-01T130102)
GIT_COMMIT_DATE=$(date +"%Y-%m-%dT%H%M%S" --date=@$(git show --no-patch --format=%ct HEAD))

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please consult build instructions." 
   exit 1
fi

if [ "$CODENAME" = "INVALID" ] || [ "$ARCH" = "INVALID" ]; then
  echo "The variable CODENAME=${CODENAME} or ARCH=${ARCH} was not set correctly. Are you using the Makefile? Please consult build instructions."
  exit 1
fi

# Disable the debootstrap GPG validation for Ubuntu 18.04 (Bionic) after its public key
# failed to validate on the Docker build environment container for an unclear reason.
# See [1] for full write-up.
#
# [1] https://github.com/rescuezilla/rescuezilla/issues/538
GPG_CHECK_OPTS=""
if [ "$CODENAME" = "bionic" ]; then
    GPG_CHECK_OPTS="--no-check-gpg"
fi

# debootstrap part 1/2: If package cache doesn't exist, download the packages
# used in a base Debian system into the package cache directory [1]
#
# [1] https://unix.stackexchange.com/a/397966
if [ ! -d "$PKG_CACHE_DIRECTORY/$DEBOOTSTRAP_CACHE_DIRECTORY" ] ; then
    mkdir -p $PKG_CACHE_DIRECTORY/$DEBOOTSTRAP_CACHE_DIRECTORY
    # Selecting a geographically closer APT mirror may increase network transfer rates.
    #
    # Note: After the support window for a specific release ends, the packages are moved to the 'old-releases' 
    # URL [1], which means substitution becomes mandatory in-order to build older releases from scratch.
    #
    # [1] http://old-releases.ubuntu.com/ubuntu
    TARGET_FOLDER=`readlink -f $PKG_CACHE_DIRECTORY/$DEBOOTSTRAP_CACHE_DIRECTORY`
    pushd ${DEBOOTSTRAP_SCRIPT_DIRECTORY}
    #DEBOOTSTRAP_DIR=${DEBOOTSTRAP_SCRIPT_DIRECTORY} ./debootstrap ${GPG_CHECK_OPTS} --arch=$ARCH --foreign $CODENAME $TARGET_FOLDER http://archive.ubuntu.com/ubuntu/
    DEBOOTSTRAP_DIR=${DEBOOTSTRAP_SCRIPT_DIRECTORY} ./debootstrap ${GPG_CHECK_OPTS} --arch=$ARCH --foreign $CODENAME $TARGET_FOLDER  http://ports.ubuntu.com/ubuntu-ports/
    RET=$?
    popd
    if [[ $RET -ne 0 ]]; then
        echo "debootstrap part 1/2 failed. This may occur if you're using an older version of deboostrap"
        echo "that doesn't have a script for \"$CODENAME\". Please consult the build instructions." 
        exit 1
    fi
fi

echo "Copy debootstrap package cache"
rsync --archive "$PKG_CACHE_DIRECTORY/$DEBOOTSTRAP_CACHE_DIRECTORY/" "$BUILD_DIRECTORY/chroot/"
RET=$?
if [[ $RET -ne 0 ]]; then
    echo "Failed to copy"
    exit 1
fi
 
# debootstrap part 2/2: Bootstrap a Debian root filesystem based on cached packages directory (part 2/2)
chroot $BUILD_DIRECTORY/chroot/ /bin/bash -c "DEBOOTSTRAP_DIR=\"debootstrap\" ./debootstrap/debootstrap --second-stage ${GPG_CHECK_OPTS}"
RET=$?
if [[ $RET -ne 0 ]]; then
    echo "debootstrap part 2/2 failed. This may occur if the package cache ($PKG_CACHE_DIRECTORY/$DEBOOTSTRAP_CACHE_DIRECTORY/)"
    echo "exists but is not fully populated. If so, deleting this directory might help. Please consult the build instructions." 
    exit 1
fi

# Ensures tmp directory has correct mode, including sticky-bit
chmod 1777 "$BUILD_DIRECTORY/chroot/tmp/"

# Copy cached apt packages, if present, to reduce need to download packages from internet
if [ -d "$PKG_CACHE_DIRECTORY/$APT_PKG_CACHE_DIRECTORY/" ] ; then
    mkdir -p "$BUILD_DIRECTORY/chroot/var/cache/apt/archives/"
    echo "Copy apt package cache"
    rsync --archive "$PKG_CACHE_DIRECTORY/$APT_PKG_CACHE_DIRECTORY/" "$BUILD_DIRECTORY/chroot/var/cache/apt/archives"
    RET=$?
    if [[ $RET -ne 0 ]]; then
        echo "Failed to copy"
        exit 1
    fi
fi

# Copy cached apt indexes, if present, to a temporary directory, to reduce need to download packages from internet.
if [ -d "$PKG_CACHE_DIRECTORY/$APT_INDEX_CACHE_DIRECTORY/" ] ; then
    mkdir -p "$BUILD_DIRECTORY/chroot/var/lib/apt/"
    echo "Copy apt index cache"
    rsync --archive "$PKG_CACHE_DIRECTORY/$APT_INDEX_CACHE_DIRECTORY/" "$BUILD_DIRECTORY/chroot/var/lib/apt/lists.cache"
    RET=$?
    if [[ $RET -ne 0 ]]; then
        echo "Failed to copy"
        exit 1
    fi
fi

cd "$BUILD_DIRECTORY"
# Enter chroot, and launch next stage of script
mount --bind /dev chroot/dev

# Copy files related to network connectivity
cp /etc/hosts chroot/etc/hosts
cp /etc/resolv.conf chroot/etc/resolv.conf

# Copy the CHANGELOG
rsync --archive "$BASEDIR/CHANGELOG" "$BUILD_DIRECTORY/chroot/usr/share/rescuezilla/"
RET=$?
if [[ $RET -ne 0 ]]; then
    echo "Failed to copy"
    exit 1
fi

# Synchronize apt package manager configuration files
rsync --archive "$BASEDIR/src/livecd/chroot/etc/apt/" "$BUILD_DIRECTORY/chroot/etc/apt"
RET=$?
if [[ $RET -ne 0 ]]; then
    echo "Failed to copy"
    exit 1
fi

if  [ "$IS_INTEGRATION_TEST" == "true" ]; then
    LINUX_QUERY_SERVER_INSTALLER="$BASEDIR/src/integration-test/scripts/install-linux-query-tcp-server.sh"
    rsync --archive "$LINUX_QUERY_SERVER_INSTALLER" "$BUILD_DIRECTORY/chroot/"
    RET=$?
    if [[ $RET -ne 0 ]]; then
        echo "Failed to copy"
        exit 1
    fi
fi

# Renames the apt-preferences file to ensure backports and proposed
# repositories for the desired code name are never automatically selected.
pushd "chroot/etc/apt/preferences.d/"
mv "89_CODENAME_SUBSTITUTE-backports_default" "89_$CODENAME-backports_default"
mv "90_CODENAME_SUBSTITUTE-proposed_default" "90_$CODENAME-proposed_default"
popd

mv "chroot/etc/apt/sources.list.d/mozillateam-ubuntu-ppa-CODENAME_SUBSTITUTE.list" "chroot/etc/apt/sources.list.d/mozillateam-ubuntu-ppa-$CODENAME.list"

pushd "chroot/etc/apt/sources.list.d/"
# Since Ubuntu 22.04 (Jammy) firefox packaged as snap, which is not easily installed in a chroot
# [1] https://bugs.launchpad.net/snappy/+bug/1609903
mv "mozillateam-ubuntu-ppa-CODENAME_SUBSTITUTE.list" "mozillateam-ubuntu-ppa-CODENAME_SUBSTITUTE.list"
popd
APT_CONFIG_FILES=(
    "chroot/etc/apt/preferences.d/89_$CODENAME-backports_default"
    "chroot/etc/apt/preferences.d/90_$CODENAME-proposed_default"
    "chroot/etc/apt/sources.list.d/mozillateam-ubuntu-ppa-$CODENAME.list"
    "chroot/etc/apt/sources.list"
)
# Substitute Ubuntu code name into relevant apt configuration files
for apt_config_file in "${APT_CONFIG_FILES[@]}"; do
  sed --in-place s/CODENAME_SUBSTITUTE/$CODENAME/g $apt_config_file
done

cp "$BASEDIR/src/scripts/chroot-steps-part-1.sh" "$BASEDIR/src/scripts/chroot-steps-part-2.sh" chroot
# Launch first stage chroot. In other words, run commands within the root filesystem
# that is being constructed using binaries from within that root filesystem.
chroot chroot/ /bin/bash -c "IS_INTEGRATION_TEST=$IS_INTEGRATION_TEST ARCH=$ARCH CODENAME=$CODENAME /chroot-steps-part-1.sh"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to execute chroot steps part 1."
    exit 1
fi

rm "$BUILD_DIRECTORY/chroot/install-linux-query-tcp-server.sh"

cd "$BASEDIR"
# Copy the source FHS filesystem tree onto the build's chroot FHS tree, overwriting the base files where conflicts occur.
# The only exception the apt package manager configuration files which have already been copied above.
rsync --archive --exclude "chroot/etc/apt" src/livecd/ "$BUILD_DIRECTORY"
RET=$?
if [[ $RET -ne 0 ]]; then
    echo "Failed to copy"
    exit 1
fi

cp --archive $BUILD_DIRECTORY/../*.deb "$BUILD_DIRECTORY/chroot/"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to copy Rescuezilla deb packages."
    exit 1
fi

# Create desktop icon shortcuts
ln -s /usr/share/applications/rescuezilla.desktop "$BUILD_DIRECTORY/chroot/home/ubuntu/Desktop/rescuezilla.desktop"
ln -s /usr/share/applications/org.xfce.mousepad.desktop "$BUILD_DIRECTORY/chroot/home/ubuntu/Desktop/mousepad.desktop"
ln -s /usr/share/applications/gparted.desktop "$BUILD_DIRECTORY/chroot/home/ubuntu/Desktop/gparted.desktop"

if  [ "$CODENAME" == "oracular" ]; then
  # HACK: Remove the Firefox desktop shortcut that this build system copied in earlier
  # as Oracular doesn't have a mozillateam PPA based Firefox unlike earlier releases
  rm "$BUILD_DIRECTORY/chroot/home/ubuntu/Desktop/firefox.desktop"
fi

# Process GRUB locale files
pushd "$BUILD_DIRECTORY/image/boot/grub/locale/"
for grub_po_file in *.po; do
        if [[ ! -f "$grub_po_file" ]]; then
                echo "Warning: $grub_po_file translation does not exist. Skipping."
        else
                # Remove .po extension from filename
                lang=$(echo "$grub_po_file" | cut -f 1 -d '.')
                echo "Converting language translation file: $BUILD_DIRECTORY/image/boot/grub/locale/$grub_po_file to $lang.mo" 
                msgfmt --output-file="$lang.mo" "$grub_po_file"
                if [[ $? -ne 0 ]]; then
                        echo "Error: Unable to convert GRUB bootloader configuration $lang translation from text-based po format to binary mo format."
                        exit 1
                fi
                # Remove unused *.po file
                rm "$grub_po_file"
        fi
done
popd

# Most end-users will not understand the terms i386 and AMD64.
MEMORY_BUS_WIDTH=""
if  [ "$ARCH" == "i386" ]; then
  MEMORY_BUS_WIDTH="32bit"
elif  [ "$ARCH" == "amd64" ]; then
  MEMORY_BUS_WIDTH="64bit"
elif  [ "$ARCH" == "arm64" ]; then
  MEMORY_BUS_WIDTH="64bit"
else
    echo "Warning: unknown register width $ARCH"
fi

SUBSTITUTIONS=(
    # GRUB boot menu 
    "$BUILD_DIRECTORY/image/boot/grub/theme/theme.txt"
    # Firefox browser homepage query-string, to be able to provide a "You are using an old version. Please update."
    # message when users open the web browser with a (inevitably) decades old version.
    "$BUILD_DIRECTORY/chroot/usr/lib/firefox/distribution/policies.json"
)
for file in "${SUBSTITUTIONS[@]}"; do
    # Substitute version into file
    sed --in-place s/VERSION-SUBSTITUTED-BY-BUILD-SCRIPT/${VERSION_STRING}/g $file
    # Substitute CPU architecture description into file
    sed --in-place s/ARCH-SUBSTITUTED-BY-BUILD-SCRIPT/${ARCH}/g $file
    # Substitute CPU human-readable CPU architecture into file
    sed --in-place s/MEMORY-BUS-WIDTH-SUBSTITUTED-BY-BUILD-SCRIPT/${MEMORY_BUS_WIDTH}/g $file
    # Substitute date
    sed --in-place s/GIT-COMMIT-DATE-SUBSTITUTED-BY-BUILD-SCRIPT/${GIT_COMMIT_DATE}/g $file
done

# Enter chroot again
cd "$BUILD_DIRECTORY"
chroot chroot/ /bin/bash /chroot-steps-part-2.sh
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to execute chroot steps part 2."
    exit 1
fi

rsync --archive chroot/var.cache.apt.archives/ "$BASEDIR/$PKG_CACHE_DIRECTORY/$APT_PKG_CACHE_DIRECTORY"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to copy."
    exit 1
fi

rm -rf chroot/var.cache.apt.archives
rsync --archive chroot/var.lib.apt.lists/ "$BASEDIR/$PKG_CACHE_DIRECTORY/$APT_INDEX_CACHE_DIRECTORY"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to copy."
    exit 1
fi
rm -rf chroot/var.lib.apt.lists

umount -lf chroot/dev/
rm chroot/root/.bash_history
rm chroot/chroot-steps-part-1.sh chroot/chroot-steps-part-2.sh

# 修复：验证 ARM64 内核文件是否存在
mkdir -p image/casper image/memtest

# 检查内核文件
echo "检查 ARM64 内核文件..."
if ! ls chroot/boot/vmlinuz-*-generic 2>/dev/null | grep -q vmlinuz; then
    echo "错误：未找到 ARM64 内核。尝试在 chroot 中查找..."
    chroot chroot/ /bin/bash -c "find /boot -name 'vmlinuz*' -type f"
    echo "请确保在 chroot 中安装了 linux-image-generic 包。"
    exit 1
fi

cp chroot/boot/vmlinuz-*-generic image/casper/vmlinuz
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to copy vmlinuz image."
    exit 1
fi
# Ensures compressed Linux kernel image is readable during the MD5 checksum at boot
chmod 644 image/casper/vmlinuz

# 检查 initrd 文件
if ! ls chroot/boot/initrd.img-*-generic 2>/dev/null | grep -q initrd.img; then
    echo "错误：未找到 ARM64 initrd。尝试在 chroot 中查找..."
    chroot chroot/ /bin/bash -c "find /boot -name 'initrd*' -type f"
    exit 1
fi

cp chroot/boot/initrd.img-*-generic image/casper/initrd.lz
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to copy initrd image."
    exit 1
fi

# Create manifest
chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' > image/casper/filesystem.manifest
cp -v image/casper/filesystem.manifest image/casper/filesystem.manifest-desktop
REMOVE=("ubiquity"
        "ubiquity-frontend-gtk"
        "ubiquity-frontend-kde"
        "casper"
        "live-initramfs"
        "user-setup"
        "discover"
        "xresprobe"
        "os-prober"
        "libdebian-installer4"
)
for remove in "${REMOVE[@]}"
do
     sed -i "/${remove}/d" image/casper/filesystem.manifest-desktop
done

cat << EOF > image/README.diskdefines
#define DISKNAME Rescuezilla
#define TYPE binary
#define TYPEbinary 1
#define ARCH $ARCH
#define ARCH$ARCH 1
#define DISKNUM 1
#define DISKNUM1 1
#define TOTALNUM 0
#define TOTALNUM0 1
EOF

touch image/ubuntu
mkdir image/.disk
cd image/.disk
touch base_installable
echo "full_cd/single" > cd_type
echo "Ubuntu Remix" > info
echo "https://rescuezilla.com" > release_notes_url
cd ../..

rm -rf image/casper/filesystem.squashfs "$RESCUEZILLA_ISO_FILENAME"

echo "Compressing squashfs using zstandard (rather than default gzip)."
if  [ "$IS_INTEGRATION_TEST" == "true" ]; then
    echo "Using lowest possible compression level of 1 to speed up compression for debug builds." 
    COMPRESSION_LEVEL=1
else
    echo "Using max compression level of 19. The compression time is greatly increased, but the decompression time "
    echo "is the same as gzip (though uses more memory). The benefit is the compression ratio is improved over gzip."
    COMPRESSION_LEVEL=19
fi

mksquashfs chroot image/casper/filesystem.squashfs -comp zstd -b 1M -Xcompression-level "${COMPRESSION_LEVEL}" -e boot -e /sys
printf $(sudo du -sx --block-size=1 chroot | cut -f1) > image/casper/filesystem.size
cd image

# 修复：ARM64 EFI 引导配置 - 从 chroot 中复制文件，而不是从 host
if [ "$ARCH" == "arm64" ]; then
    echo "设置 ARM64 UEFI 引导..."
    mkdir --parents "$BUILD_DIRECTORY/image/EFI/BOOT/"
    
    # 从 chroot 中查找 ARM64 UEFI 引导文件
    echo "在 chroot 中查找 ARM64 UEFI 引导文件..."
    
    # 检查 chroot 中的常见位置
    CHROOT_GRUB_PATHS=(
        "$BUILD_DIRECTORY/chroot/usr/lib/grub/arm64-efi/grubaa64.efi"
        "$BUILD_DIRECTORY/chroot/usr/share/grub/arm64-efi/grubaa64.efi"
        "$BUILD_DIRECTORY/chroot/usr/lib/grub-efi-arm64/grubaa64.efi"
        "$BUILD_DIRECTORY/chroot/usr/lib/grub-efi-arm64-signed/grubaa64.efi.signed"
        "$BUILD_DIRECTORY/chroot/boot/grub/arm64-efi/grubaa64.efi"
    )
    
    FOUND_BOOTLOADER=false
    for location in "${CHROOT_GRUB_PATHS[@]}"; do
        if [ -f "$location" ]; then
            echo "从 chroot 中找到 ARM64 UEFI 引导程序: $location"
            cp "$location" "$BUILD_DIRECTORY/image/EFI/BOOT/BOOTAA64.EFI"
            FOUND_BOOTLOADER=true
            break
        fi
    done
    
    # 如果没找到，尝试在 chroot 中生成
    if [ "$FOUND_BOOTLOADER" = false ]; then
        echo "在 chroot 中未找到预编译的 ARM64 UEFI 引导程序。尝试生成..."
        # 在 chroot 中生成 grubaa64.efi
        chroot "$BUILD_DIRECTORY/chroot" /bin/bash -c "
            if command -v grub-mkimage > /dev/null; then
                echo '在 chroot 中使用 grub-mkimage 生成 ARM64 UEFI 引导程序...'
                grub-mkimage --directory=/usr/lib/grub/arm64-efi \
                    --prefix=/boot/grub \
                    --output=/tmp/grubaa64.efi \
                    --format=arm64-efi \
                    --compression=auto \
                    part_gpt part_msdos fat ext2 normal boot linux configfile loopback chain efifwsetup efi_gop \
                    efi_uga ls search search_label search_fs_uuid search_fs_file gfxterm gfxterm_background \
                    gfxterm_menu test all_video loadenv exfat ntfs btrfs hfsplus iso9660 udf
                echo 'ARM64 UEFI 引导程序生成成功'
            else
                echo '错误: chroot 中没有 grub-mkimage 命令'
                exit 1
            fi
        "
        
        if [ -f "$BUILD_DIRECTORY/chroot/tmp/grubaa64.efi" ]; then
            cp "$BUILD_DIRECTORY/chroot/tmp/grubaa64.efi" "$BUILD_DIRECTORY/image/EFI/BOOT/BOOTAA64.EFI"
            FOUND_BOOTLOADER=true
            echo "已从 chroot 复制生成的 ARM64 UEFI 引导程序"
        fi
    fi
    
    # 最终检查
    if [ "$FOUND_BOOTLOADER" = false ]; then
        echo "错误：无法找到或生成 ARM64 UEFI 引导程序。"
        echo "请确保在 chroot 中安装了以下包："
        echo "  apt-get install grub-efi-arm64 grub-efi-arm64-bin grub-efi-arm64-signed"
        exit 1
    fi
    
    echo "ARM64 UEFI 引导程序已复制到: $BUILD_DIRECTORY/image/EFI/BOOT/BOOTAA64.EFI"
    
    # 复制 GRUB 模块
    if [ -d "$BUILD_DIRECTORY/chroot/usr/lib/grub/arm64-efi" ]; then
        mkdir -p "$BUILD_DIRECTORY/image/boot/grub/arm64-efi"
        cp -r "$BUILD_DIRECTORY/chroot/usr/lib/grub/arm64-efi/"* "$BUILD_DIRECTORY/image/boot/grub/arm64-efi/"
        echo "已复制 ARM64 GRUB 模块"
    elif [ -d "$BUILD_DIRECTORY/chroot/usr/lib/grub-efi-arm64" ]; then
        mkdir -p "$BUILD_DIRECTORY/image/boot/grub/arm64-efi"
        cp -r "$BUILD_DIRECTORY/chroot/usr/lib/grub-efi-arm64/"* "$BUILD_DIRECTORY/image/boot/grub/arm64-efi/"
        echo "已复制 ARM64 GRUB 模块 (替代路径)"
    else
        echo "警告：在 chroot 中未找到 ARM64 GRUB 模块。"
        mkdir -p "$BUILD_DIRECTORY/image/boot/grub/arm64-efi"
    fi
    
    # 创建 GRUB 字体目录并复制字体
    mkdir -p "$BUILD_DIRECTORY/image/boot/grub/fonts"
    if [ -f "$BUILD_DIRECTORY/chroot/usr/share/grub/unicode.pf2" ]; then
        cp "$BUILD_DIRECTORY/chroot/usr/share/grub/unicode.pf2" "$BUILD_DIRECTORY/image/boot/grub/fonts/"
        echo "已复制 GRUB 字体"
    else
        echo "警告：在 chroot 中未找到 unicode.pf2 字体文件。"
    fi
    
    # 创建 ARM64 的 GRUB 配置文件
    echo "创建 ARM64 GRUB 配置文件..."
    mkdir -p "$BUILD_DIRECTORY/image/boot/grub"
    cat > "$BUILD_DIRECTORY/image/boot/grub/grub.cfg" << 'EOF'
set default="0"
set timeout=5

menuentry "Rescuezilla (ARM64)" {
    linux /casper/vmlinuz boot=casper quiet splash noprompt noeject ---
    initrd /casper/initrd.lz
}

menuentry "Rescuezilla (ARM64) - Safe Graphics Mode" {
    linux /casper/vmlinuz boot=casper nomodeset quiet splash noprompt noeject ---
    initrd /casper/initrd.lz
}

menuentry "Rescuezilla (ARM64) - Text Mode" {
    linux /casper/vmlinuz boot=casper textonly noprompt noeject ---
    initrd /casper/initrd.lz
}

menuentry "Boot from first hard disk" {
    exit
}
EOF
    echo "ARM64 GRUB 配置文件已创建"
    
    # 创建 ESP 镜像
    echo "创建 ARM64 ESP 镜像..."
    ESP_FAT_IMAGE="$BUILD_DIRECTORY/image/boot/esp.img"
    rm -f "$ESP_FAT_IMAGE"
    dd if=/dev/zero of="$ESP_FAT_IMAGE" bs=1M count=10
    if [[ $? -ne 0 ]]; then
        echo "错误：无法创建 ESP 空白文件。"
        exit 1
    fi
    
    mkfs.fat -F 32 "$ESP_FAT_IMAGE"
    if [[ $? -ne 0 ]]; then
        echo "错误：无法创建 FAT32 文件系统。"
        exit 1
    fi
    
    # 将 EFI 目录复制到 ESP 镜像中
    mmd -i "$ESP_FAT_IMAGE" ::/EFI
    mmd -i "$ESP_FAT_IMAGE" ::/EFI/BOOT
    mcopy -i "$ESP_FAT_IMAGE" "$BUILD_DIRECTORY/image/EFI/BOOT/BOOTAA64.EFI" ::/EFI/BOOT/
    if [[ $? -ne 0 ]]; then
        echo "错误：无法复制 EFI 引导程序到 ESP 镜像。"
        exit 1
    fi
    
    echo "ARM64 ESP 镜像创建成功: $ESP_FAT_IMAGE"
    
else
    # 原始 x86 代码 (ARM64 不会执行此部分)
    mkdir --parents "$BUILD_DIRECTORY/image/EFI/BOOT/"
    cp /usr/lib/shim/shimx64.efi.signed "$BUILD_DIRECTORY/image/EFI/BOOT/BOOTx64.EFI"
    cp /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed "$BUILD_DIRECTORY/image/EFI/BOOT/grubx64.efi"
    cp -r /usr/lib/grub/x86_64-efi "$BUILD_DIRECTORY/image/boot/grub/"
    mkdir "$BUILD_DIRECTORY/image/boot/grub/fonts"
    cp /usr/share/grub/unicode.pf2 "$BUILD_DIRECTORY/image/boot/grub/fonts"
    cp /usr/lib/grub/i386-efi/monolithic/grubia32.efi "$BUILD_DIRECTORY/image/EFI/BOOT/BOOTIA32.EFI"
    cp -r /usr/lib/grub/i386-efi "$BUILD_DIRECTORY/image/boot/grub/"
    cp -r /usr/lib/grub/i386-pc "$BUILD_DIRECTORY/image/boot/grub/"
    
    ESP_FAT_IMAGE="$BUILD_DIRECTORY/image/boot/esp.img"
    rm "$ESP_FAT_IMAGE"
    dd if=/dev/zero of="$ESP_FAT_IMAGE" count=6 bs=1M
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create blank file for EFI System Partition."
        exit 1
    fi
    
    mkfs.msdos "$ESP_FAT_IMAGE"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create MSDOS filesystem for EFI System Partition (ESP)."
        exit 1
    fi
    
    mcopy -s -i "$ESP_FAT_IMAGE" "$BUILD_DIRECTORY/image/EFI" ::
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to pack EFI System Partition directory structure into FAT filesystem."
        exit 1
    fi
    
    grub-mkimage --format i386-pc-eltorito --output "$BUILD_DIRECTORY/image/boot/grub/grub.eltorito.bootstrap.img" --compression auto --prefix /boot/grub boot linux search normal configfile part_gpt fat iso9660 biosdisk test keystatus gfxmenu regexp probe efiemu all_video gfxterm font echo read ls cat png jpeg halt reboot part_msdos biosdisk
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create the GRUB bootstrap image required for El Torito CD-ROM boot."
        exit 1
    fi
fi

# Generate md5sum for files in the image
find . -type f -print0 | xargs -0 md5sum | grep -v "./md5sum.txt" > md5sum.txt

# 创建 ARM64 ISO 镜像 - 简化版
# 创建 ARM64 ISO 镜像 - 直接方法
if [ "$ARCH" == "arm64" ]; then
    echo "创建 ARM64 ISO 镜像（直接方法）..."
    
    # 进入 image 目录
    cd "$BUILD_DIRECTORY/image"
    
    # 创建 ISO（忽略传统引导，只支持 UEFI）
    xorriso \
        -as mkisofs \
        -r -J \
        -o "../$RESCUEZILLA_ISO_FILENAME" \
        -V 'RESCUEZILLA' \
        -e boot/esp.img \
        -no-emul-boot \
        -append_partition 2 0xef boot/esp.img \
        -appended_part_as_gpt \
        .
    
    if [ $? -eq 0 ] && [ -f "../$RESCUEZILLA_ISO_FILENAME" ]; then
        echo "✅ ISO 创建成功"
    else
        echo "❌ ISO 创建失败，尝试备选方法..."
        
        # 备选方法：使用 genisoimage（如果可用）
        if command -v genisoimage > /dev/null; then
            echo "使用 genisoimage 创建 ISO..."
            genisoimage \
                -o "../$RESCUEZILLA_ISO_FILENAME" \
                -V 'RESCUEZILLA' \
                -r -J \
                -e boot/esp.img \
                -no-emul-boot \
                -b boot/esp.img \
                .
        elif command -v mkisofs > /dev/null; then
            echo "使用 mkisofs 创建 ISO..."
            mkisofs \
                -o "../$RESCUEZILLA_ISO_FILENAME" \
                -V 'RESCUEZILLA' \
                -r -J \
                -e boot/esp.img \
                -no-emul-boot \
                -b boot/esp.img \
                .
        else
            echo "错误：没有找到可用的 ISO 创建工具。"
            exit 1
        fi
    fi
    
    # 验证 ISO
    if [ -f "../$RESCUEZILLA_ISO_FILENAME" ]; then
        echo "ISO 创建成功: ../$RESCUEZILLA_ISO_FILENAME"
        echo "文件大小: $(ls -lh "../$RESCUEZILLA_ISO_FILENAME" | awk '{print $5}')"
    else
        echo "错误：ISO 文件未创建。"
        exit 1
    fi
    
    cd "$BUILD_DIRECTORY"
    mv "$BUILD_DIRECTORY/$RESCUEZILLA_ISO_FILENAME" ../
    
    echo "构建完成！"
fi

#cd "$BUILD_DIRECTORY"
#mv "$BUILD_DIRECTORY/$RESCUEZILLA_ISO_FILENAME" ../

echo "构建完成！ISO 文件位于: ../$RESCUEZILLA_ISO_FILENAME"

# TODO: Evaluate the "Errata" sections of the Redo Backup and Recovery
# TODO: Sourceforge Wiki, and determine if the build scripts need modification.
