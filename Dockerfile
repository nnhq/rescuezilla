# Typically, constructing a Linux live image relies on files from the host system. This Dockerfile,
# a version-controlled mechanism to produce a host system for live image builds.

# Note: the host system Ubuntu version (below) is defined separately from the version of the
# generated Ubuntu image.
ARG CODENAME=noble
FROM ubuntu:${CODENAME}
# Define the Ubuntu code name again because Docker clears the argument after the FROM command.
ARG CODENAME=noble

# Set the target architecture to ARM64
ARG TARGETARCH=arm64
ENV DEBIAN_TARGET_ARCH=arm64

# Copy the apt repository mirror list into the Docker image.
# 
# For increased transfer rates, consider selecting a mirror geographically
# closer mirror.
# 
# Note: After the support window for a specific release ends, the packages are
# moved to the 'old-releases' URL, which makes substitution becomes mandatory
# in-order to build older releases from scratch.
#
RUN echo $CODENAME
COPY src/livecd/chroot/etc/apt/sources.list.arm64 /etc/apt/sources.list
# Copy the apt-preferences file to ensure backports and proposed repositories are never automatically selected.
COPY "src/livecd/chroot/etc/apt/preferences.d/89_CODENAME_SUBSTITUTE-backports_default" "/etc/apt/preferences.d/89_$CODENAME-backports_default"
COPY "src/livecd/chroot/etc/apt/preferences.d/90_CODENAME_SUBSTITUTE-proposed_default" "/etc/apt/preferences.d/90_$CODENAME-proposed_default"
RUN sed --in-place "s*CODENAME_SUBSTITUTE*$CODENAME*g" "/etc/apt/sources.list"
RUN sed --in-place "s*CODENAME_SUBSTITUTE*$CODENAME*g" /etc/apt/preferences.d/89_${CODENAME}-backports_default
RUN sed --in-place "s*CODENAME_SUBSTITUTE*$CODENAME*g" /etc/apt/preferences.d/90_${CODENAME}-proposed_default

# Ensure all Dockerfile package installation operations are non-interactive, DEBIAN_FRONTEND=noninteractive is insufficient [1]
# [1] https://github.com/phusion/baseimage-docker/issues/58
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Configure dpkg to support multi-arch for ARM64 cross-compilation if needed
RUN dpkg --add-architecture arm64

# Refresh the apt package metadata
RUN apt-get update

# Install QEMU user static for cross-compilation support if building on x86_64
RUN if [ "$(uname -m)" = "x86_64" ]; then \
        apt-get install --yes qemu-user-static binfmt-support; \
    fi

RUN apt-get install --yes \
                          # Install required dependencies for the build
                          make rsync sudo debootstrap squashfs-tools xorriso git git-lfs gettext \
                          dosfstools mtools checkinstall cmake time \
                          # ARM64 UEFI boot components (remove x86/amd64 specific packages)
                          shim-signed grub-efi-arm64 grub-efi-arm64-bin grub-efi-arm64-signed \
                          devscripts debhelper ccache \
                          # Dependencies for "sfdisk" and "partclone.restore" build for ARM64
                          libtool-bin gawk pkg-config comerr-dev docbook-xsl e2fslibs-dev fuse3 \
                          libaal-dev libblkid-dev libbsd-dev libext2fs-dev libncurses5-dev \
                          libncursesw5-dev libreadline-dev libreadline8 \
                          libreiser4-dev libtinfo-dev libxslt1.1 nilfs-tools ntfs-3g ntfs-3g-dev \
                          quilt sgml-base uuid-dev vmfs-tools xfslibs-dev xfsprogs xml-core \
                          xsltproc libssl-dev \
                          # ARM64 cross-compilation toolchain (if building on non-ARM64 host)
                          gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
                          libc6-dev-arm64-cross \
                          # Select runtime dependencies required for running the unit tests
                          python3-gi libgtk-3-dev python3-whichcraft python3-babel \
                          # Install optional dependencies for quality-of-life when debugging
                          tmux vim

# Set up cross-compilation environment variables if needed
ENV CC_FOR_TARGET=aarch64-linux-gnu-gcc
ENV CXX_FOR_TARGET=aarch64-linux-gnu-g++
ENV AR_FOR_TARGET=aarch64-linux-gnu-ar
ENV STRIP_FOR_TARGET=aarch64-linux-gnu-strip
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig

# Restore interactivity of package installation within Docker
RUN echo 'debconf debconf/frontend select Dialog' | debconf-set-selections