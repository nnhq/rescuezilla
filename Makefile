# 文件开头添加变量定义
UEFI_ONLY ?= 0

# ARM64 目标定义
focal-arm64: ARCH=arm64
focal-arm64: CODENAME=focal
export ARCH CODENAME
focal-arm64: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) UEFI_ONLY=$(UEFI_ONLY) /usr/bin/time ./src/scripts/build.sh

jammy-arm64: ARCH=arm64
jammy-arm64: CODENAME=jammy
export ARCH CODENAME
jammy-arm64: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) UEFI_ONLY=$(UEFI_ONLY) /usr/bin/time ./src/scripts/build.sh

oracular-arm64: ARCH=arm64
oracular-arm64: CODENAME=oracular
export ARCH CODENAME
oracular-arm64: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) UEFI_ONLY=$(UEFI_ONLY) /usr/bin/time ./src/scripts/build.sh

plucky-arm64: ARCH=arm64
plucky-arm64: CODENAME=plucky
export ARCH CODENAME
plucky-arm64: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) UEFI_ONLY=$(UEFI_ONLY) /usr/bin/time ./src/scripts/build.sh

noble-arm64: ARCH=arm64
noble-arm64: CODENAME=noble
export ARCH CODENAME
noble-arm64: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) UEFI_ONLY=$(UEFI_ONLY) /usr/bin/time ./src/scripts/build.sh

# 修改现有目标以支持 UEFI_ONLY 参数
focal: ARCH=amd64
focal: CODENAME=focal
export ARCH CODENAME
focal: deb sfdisk.v2.20.1.amd64 partclone-latest partclone-nbd $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) UEFI_ONLY=$(UEFI_ONLY) /usr/bin/time ./src/scripts/build.sh

# 为其他 AMD64 目标添加 UEFI_ONLY 参数（jammy, oracular, plucky, noble）

# ARM64 deb 包构建
deb-arm64: DEB_BUILD_DIR=$(abspath $(BASE_BUILD_DIRECTORY))/deb-arm64
deb-arm64:
	mkdir --parents $(DEB_BUILD_DIR)
	cd src/apps/rescuezilla/ && DEB_BUILD_DIR=$(DEB_BUILD_DIR) ARCH=arm64 $(MAKE) && mv $(DEB_BUILD_DIR)/rescuezilla_*.deb  $(DEB_BUILD_DIR)/../
	cd src/apps/graphical-shutdown/ && DEB_BUILD_DIR=$(DEB_BUILD_DIR) ARCH=arm64 $(MAKE) && mv $(DEB_BUILD_DIR)/graphical-shutdown_*.deb  $(DEB_BUILD_DIR)/../

# ARM64 sfdisk 构建
sfdisk.v2.20.1.arm64: SRC_DIR=$(shell pwd)/src/third-party/util-linux
sfdisk.v2.20.1.arm64: ARM64_BUILD_DIR=$(BASE_BUILD_DIRECTORY)/$(CODENAME).$(ARCH)
sfdisk.v2.20.1.arm64: UTIL_LINUX_BUILD_DIR=$(ARM64_BUILD_DIR)/util-linux
sfdisk.v2.20.1.arm64:
	mkdir --parents $(UTIL_LINUX_BUILD_DIR) $(ARM64_BUILD_DIR)/chroot/usr/sbin/
	cd $(UTIL_LINUX_BUILD_DIR) && $(SRC_DIR)/autogen.sh
	cd $(UTIL_LINUX_BUILD_DIR) && $(SRC_DIR)/configure --without-ncurses --host=aarch64-linux-gnu
	cd $(UTIL_LINUX_BUILD_DIR) && make CC='ccache aarch64-linux-gnu-gcc' -j $(THREADS)
	mv $(UTIL_LINUX_BUILD_DIR)/fdisk/sfdisk $(ARM64_BUILD_DIR)/chroot/usr/sbin/sfdisk.v2.20.1.64bit

# ARM64 partclone-latest 构建
partclone-latest-arm64: SRC_DIR=$(shell pwd)/src/third-party/partclone-latest
partclone-latest-arm64: ARM64_BUILD_DIR=$(BASE_BUILD_DIRECTORY)/$(CODENAME).$(ARCH)
partclone-latest-arm64: PARTCLONE_LATEST_BUILD_DIR=$(ARM64_BUILD_DIR)/partclone-latest
partclone-latest-arm64: PARTCLONE_PKG_VERSION=0.3.40
partclone-latest-arm64:
	rm -rf $(PARTCLONE_LATEST_BUILD_DIR)
	mkdir --parents $(PARTCLONE_LATEST_BUILD_DIR) $(ARM64_BUILD_DIR)/chroot/
	rsync -rP "$(SRC_DIR)/" "$(PARTCLONE_LATEST_BUILD_DIR)/"
	cd $(PARTCLONE_LATEST_BUILD_DIR) && autoreconf -i
	cd $(PARTCLONE_LATEST_BUILD_DIR) && ./configure --host=aarch64-linux-gnu --enable-ncursesw --enable-static --enable-extfs --enable-reiser4 --enable-ntfs --enable-fat --enable-exfat --enable-hfsp --enable-apfs --enable-btrfs --enable-minix --enable-f2fs --enable-nilfs2
	cd $(PARTCLONE_LATEST_BUILD_DIR) && make CC='ccache aarch64-linux-gnu-gcc' -j $(THREADS)
	cd $(PARTCLONE_LATEST_BUILD_DIR) && checkinstall --install=no --pkgname partclone --pkgversion $(PARTCLONE_PKG_VERSION) --pkgrelease 1 --maintainer 'rescuezilla@gmail.com' -D --default make CC='ccache aarch64-linux-gnu-gcc' -j $(THREADS) install
	mv $(PARTCLONE_LATEST_BUILD_DIR)/partclone_$(PARTCLONE_PKG_VERSION)-1_arm64.deb $(ARM64_BUILD_DIR)/chroot/

# ARM64 partclone-nbd 构建
partclone-nbd-arm64: SRC_DIR=$(shell pwd)/src/third-party/partclone-nbd
partclone-nbd-arm64: ARM64_BUILD_DIR=$(BASE_BUILD_DIRECTORY)/$(CODENAME).$(ARCH)
partclone-nbd-arm64: PARTCLONE_NBD_BUILD_DIR=$(BASE_BUILD_DIRECTORY)/partclone-nbd-arm64
partclone-nbd-arm64:
	mkdir --parents $(PARTCLONE_NBD_BUILD_DIR) $(ARM64_BUILD_DIR)/chroot/
	cd $(PARTCLONE_NBD_BUILD_DIR) && cmake ${SRC_DIR} -DCMAKE_TOOLCHAIN_FILE=../cmake/aarch64-toolchain.cmake
	cd $(PARTCLONE_NBD_BUILD_DIR) && cpack -D CPACK_PACKAGING_INSTALL_PREFIX="/usr/local" -D CPACK_DEBIAN_PACKAGE_ARCHITECTURE=arm64 -G DEB
	mv $(PARTCLONE_NBD_BUILD_DIR)/_packages/partclone-nbd_0.0.4_arm64.deb $(ARM64_BUILD_DIR)/chroot/

# 添加 Docker 辅助目标
docker-focal-arm64:
	docker exec --interactive --workdir=/home/rescuezilla/ builder.container make focal-arm64 UEFI_ONLY=1

docker-jammy-arm64:
	docker exec --interactive --workdir=/home/rescuezilla/ builder.container make jammy-arm64 UEFI_ONLY=1

docker-oracular-arm64:
	docker exec --interactive --workdir=/home/rescuezilla/ builder.container make oracular-arm64 UEFI_ONLY=1

docker-plucky-arm64:
	docker exec --interactive --workdir=/home/rescuezilla/ builder.container make plucky-arm64 UEFI_ONLY=1

docker-noble-arm64:
	docker exec --interactive --workdir=/home/rescuezilla/ builder.container make noble-arm64 UEFI_ONLY=1
