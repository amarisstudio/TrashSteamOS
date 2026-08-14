# Build environment for linux-neptune-616 (SteamOS 3.8 kernel).
# Runs as linux/amd64 under Rosetta on Apple Silicon.
FROM --platform=linux/amd64 archlinux:base-devel

# pacman's seccomp download sandbox breaks under Rosetta emulation
# ("error restricting syscalls via seccomp") — disable it in-container.
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

# makedepends from the linux-neptune-616 PKGBUILD, plus git/openssh (source
# fetch), sudo (makepkg refuses to run as root) and zstd (package compression).
RUN pacman -Syu --noconfirm --needed \
      bc cpio gettext libelf pahole perl python tar xz \
      git openssh sudo zstd && \
    pacman -Scc --noconfirm && \
    useradd -m builder && \
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

USER builder
WORKDIR /work
