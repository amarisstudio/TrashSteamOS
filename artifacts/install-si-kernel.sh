#!/bin/bash
# One-shot installer for the SI-enabled linux-neptune-616 kernel on SteamOS 3.8.
# Run from the USB stick directory as: sudo bash install-si-kernel.sh
set -eu

cd "$(dirname "$0")"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run me with sudo: sudo bash install-si-kernel.sh" >&2
    exit 1
fi

PKGS=(linux-neptune-616-6.16*-x86_64.pkg.tar.zst)
if ! ls "${PKGS[@]}" >/dev/null 2>&1; then
    echo "Kernel packages not found next to this script." >&2
    exit 1
fi

echo "==> Staging kernel package + restore tooling in /home/deck/si-kernel (survives OS updates)"
# Kernel only — the headers package is for DKMS, depends on pahole (network
# fetch), and is not needed to boot. Install it manually later if you ever
# need to build out-of-tree modules.
mkdir -p /home/deck/si-kernel
cp linux-neptune-616-6.16*-x86_64.pkg.tar.zst restore-si-kernel.sh /home/deck/si-kernel/
chmod +x /home/deck/si-kernel/restore-si-kernel.sh
chown -R deck:deck /home/deck/si-kernel

echo "==> Disabling read-only rootfs"
steamos-readonly disable

echo "==> Installing kernel package"
# Same pkgver/pkgrel as stock: pacman will say 'reinstalling'. That is expected.
# '==> ERROR: module not found' warnings from mkinitcpio are known-harmless.
pacman -U --noconfirm /home/deck/si-kernel/linux-neptune-616-6.16*-x86_64.pkg.tar.zst

echo "==> Installing self-heal service (reinstalls kernel after SteamOS updates)"
cp si-kernel-restore.service /etc/systemd/system/si-kernel-restore.service
systemctl daemon-reload
systemctl enable si-kernel-restore.service

echo "==> Adding keep-list drop-in so the service survives atomic updates"
# NOTE: the atomic-update keep-list can ONLY preserve files under /etc. The
# kernel itself (in /usr/lib/modules) CANNOT be keep-listed; that is what the
# self-heal service is for. These patterns are already in the default keep
# list, but we pin them explicitly in case Valve ever trims the defaults.
mkdir -p /etc/atomic-update.conf.d
cat > /etc/atomic-update.conf.d/si-kernel.conf <<'EOF'
## Preserve the SI-kernel self-heal unit across SteamOS atomic updates.
## The kernel packages + restore script live in /home/deck/si-kernel/ (kept
## because /home persists); this keeps the systemd wiring that re-applies them.
/etc/systemd/system/si-kernel-restore.service
/etc/systemd/system/multi-user.target.wants/si-kernel-restore.service
EOF

echo "==> Re-enabling read-only rootfs"
steamos-readonly enable

echo
echo "Done. Reboot now. After reboot, verify with:"
echo "  zcat /proc/config.gz | grep -E 'DRM_AMDGPU_(SI|CIK)'"
echo "  sudo dmesg | grep -i amdgpu"
