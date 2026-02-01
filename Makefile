.DEFAULT_GOAL := noble-arm64-uefi
.PHONY: all focal-arm64-uefi jammy-arm64-uefi noble-arm64-uefi deb-arm64 sfdisk.v2.20.1.arm64 partclone.restore.v0.2.43.arm64 partclone-latest-arm64 partclone-utils-arm64 partclone-nbd-arm64 install test integration-test clean-build-dir clean clean-all

# Docker-related targets for ARM64
.PHONY: docker-build-arm64 docker-run-arm64 docker-add-safe-directory docker-status docker-test docker-focal-arm64-uefi docker-jammy-arm64-uefi docker-noble-arm64-uefi docker-deb-arm64

BASE_BUILD_DIRECTORY ?= $(shell pwd)/build

# Set threads variable to N-1 cpu cores.
THREADS = `cat /proc/cpuinfo | grep process | tail -1 | cut -d":" -f2 | cut -d" " -f2`

# Set shell to bash, so can use 'pipefail' to cause Make to exit when certain commands below (that pipe into tee) fails
SHELL=/bin/bash

all: noble-arm64-uefi

buildscripts = src/scripts/build.sh src/scripts/chroot-steps-part-1.sh src/scripts/chroot-steps-part-2.sh

# ISO image based on Ubuntu 20.04 Focal LTS (Long Term Support) ARM64 with UEFI
focal-arm64-uefi: ARCH=arm64
focal-arm64-uefi: CODENAME=focal
focal-arm64-uefi: UEFI_ENABLED=true
export ARCH CODENAME UEFI_ENABLED
focal-arm64-uefi: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) /usr/bin/time ./src/scripts/build.sh

# ISO image based on Ubuntu 22.04 Jammy LTS (Long Term Support) ARM64 with UEFI
jammy-arm64-uefi: ARCH=arm64
jammy-arm64-uefi: CODENAME=jammy
jammy-arm64-uefi: UEFI_ENABLED=true
export ARCH CODENAME UEFI_ENABLED
jammy-arm64-uefi: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) /usr/bin/time ./src/scripts/build.sh	

# ISO image based on Ubuntu 24.04 Noble LTS (Long Term Support) ARM64 with UEFI
noble-arm64-uefi: ARCH=arm64
noble-arm64-uefi: CODENAME=noble
noble-arm64-uefi: UEFI_ENABLED=true
export ARCH CODENAME UEFI_ENABLED
noble-arm64-uefi: deb-arm64 sfdisk.v2.20.1.arm64 partclone-latest-arm64 partclone-nbd-arm64 $(buildscripts)
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) /usr/bin/time ./src/scripts/build.sh

# Build Rescuezilla Debian package for ARM64
deb-arm64: ARCH=arm64
export ARCH
deb-arm64: sfdisk.v2.20.1.arm64 partclone.restore.v0.2.43.arm64 partclone-latest-arm64 partclone-utils-arm64 partclone-nbd-arm64 src/livecd/chroot/usr/lib/python3/dist-packages/rescuezilla
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) src/scripts/build-deb.sh

# Compile sfdisk v2.20.1 for ARM64
sfdisk.v2.20.1.arm64: ARCH=arm64
export ARCH
sfdisk.v2.20.1.arm64:
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) src/third-party/sfdisk.v2.20.1/build.sh

# Compile partclone-restore v0.2.43 for ARM64
partclone.restore.v0.2.43.arm64: ARCH=arm64
export ARCH
partclone.restore.v0.2.43.arm64:
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) src/third-party/partclone.restore.v0.2.43/build.sh

# Compile latest partclone for ARM64
partclone-latest-arm64: ARCH=arm64
export ARCH
partclone-latest-arm64:
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) src/third-party/partclone-latest/build.sh

# Compile partclone-utils for ARM64
partclone-utils-arm64: ARCH=arm64
export ARCH
partclone-utils-arm64:
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) src/third-party/partclone-utils/build.sh

# Compile partclone-nbd for ARM64
partclone-nbd-arm64: ARCH=arm64
export ARCH
partclone-nbd-arm64:
	BASE_BUILD_DIRECTORY=$(BASE_BUILD_DIRECTORY) src/third-party/partclone-nbd/build.sh

# Docker targets for ARM64 - Build on native architecture (x86_64 in GitHub Actions)
docker-build-arm64:
	@echo "Building Docker image rescuezilla-build-arm64..."
	docker build -f Dockerfile.dev -t rescuezilla-build-arm64:latest .
	@echo "Docker image built successfully"

docker-run-arm64:
	@echo "Starting Docker container rescuezilla-build-arm64..."
	docker run --rm -d --name rescuezilla-build-arm64 --privileged -v $(PWD):/rescuezilla rescuezilla-build-arm64:latest

docker-add-safe-directory:
	docker exec rescuezilla-build-arm64 bash -c "cd /rescuezilla && git config --global --add safe.directory /rescuezilla"

docker-status:
	docker exec rescuezilla-build-arm64 bash -c "cd /rescuezilla && pwd && whoami && git status"

docker-test:
	docker exec rescuezilla-build-arm64 bash -c "cd /rescuezilla && make test"

docker-focal-arm64-uefi:
	docker exec rescuezilla-build-arm64 bash -c "cd /rescuezilla && make focal-arm64-uefi"

docker-jammy-arm64-uefi:
	docker exec rescuezilla-build-arm64 bash -c "cd /rescuezilla && make jammy-arm64-uefi"

docker-noble-arm64-uefi:
	docker exec rescuezilla-build-arm64 bash -c "cd /rescuezilla && make noble-arm64-uefi"

docker-deb-arm64:
	docker exec rescuezilla-build-arm64 bash -c "cd /rescuezilla && make deb-arm64"

install:
	@echo "WARNING: The 'install' target does not work yet for ARM64 builds."
	@echo "Please file a bug report at https://github.com/rescuezilla/rescuezilla/issues to ask for this feature."

# Run unit tests for ARM64 (assume Python tests are architecture-independent)
test:
	LANG=en_GB.UTF-8 python3 -m pytest src/apps/rescuezilla/rescuezilla/test/ --capture=no

# Run integration tests for ARM64 (these would need significant modification)
integration-test:
	@echo "WARNING: Integration tests may not work correctly for ARM64."
	@echo "This would require ARM64 test images and proper configuration."
	cd src/integration-test && sudo -E ./run.all.tests.sh

clean-build-dir:
	if mountpoint -q $(BASE_BUILD_DIRECTORY)/chroot/proc/; then sudo umount $(BASE_BUILD_DIRECTORY)/chroot/proc/; fi
	if mountpoint -q $(BASE_BUILD_DIRECTORY)/chroot/sys/; then sudo umount $(BASE_BUILD_DIRECTORY)/chroot/sys/; fi
	if mountpoint -q $(BASE_BUILD_DIRECTORY)/chroot/dev/; then sudo umount $(BASE_BUILD_DIRECTORY)/chroot/dev/; fi
	if mountpoint -q $(BASE_BUILD_DIRECTORY)/chroot/tmp/; then sudo umount $(BASE_BUILD_DIRECTORY)/chroot/tmp/; fi
	sudo rm -rf $(BASE_BUILD_DIRECTORY)/

clean: clean-build-dir

clean-all: clean
	rm -rf $(BASE_BUILD_DIRECTORY)/ 
	docker stop rescuezilla-build-arm64 2>/dev/null || true
	docker rm rescuezilla-build-arm64 2>/dev/null || true
