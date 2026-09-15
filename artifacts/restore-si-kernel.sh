#!/bin/bash
# Reinstalls the SI-enabled linux-neptune-616 kernel if the running kernel
# lacks CONFIG_DRM_AMDGPU_SI (i.e. after a SteamOS atomic update replaced the
# rootfs with a stock image). Lives in /home/deck/si-kernel/ because /home
# survives atomic updates; invoked by si-kernel-restore.service, which
# survives updates via the /etc keep-list.
#
# Loop protection: if a restore was already attempted and we're STILL on a
# stock kernel, something is wrong. Stop and leave a log instead of
# reboot-cycling a headless machine.
set -u

PKGDIR=/home/deck/si-kernel
MARKER=$PKGDIR/.restore-attempted
LOG=$PKGDIR/restore.log

# Fresh install from the custom installer image: packages are baked into
# /opt/si-kernel on the rootfs. Stage them into /home on first boot so they
# survive OS updates (which replace the rootfs, /opt included).
if [ ! -e "$PKGDIR/restore-si-kernel.sh" ] && [ -d /opt/si-kernel ]; then
    mkdir -p "$PKGDIR"
    cp /opt/si-kernel/linux-neptune-616-6.16*-x86_64.pkg.tar.zst "$PKGDIR"/ 2>/dev/null || true
    cp /opt/si-kernel/restore-si-kernel.sh "$PKGDIR"/ 2>/dev/null || true
    chmod +x "$PKGDIR/restore-si-kernel.sh" 2>/dev/null || true
    chown -R 1000:1000 "$PKGDIR" 2>/dev/null || true
fi

log() { echo "$(date -Is) $*" >> "$LOG"; }

if zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_DRM_AMDGPU_SI=y'; then
    # Custom kernel is running; clear any stale attempt marker.
    rm -f "$MARKER"
    exit 0
fi

if [ -e "$MARKER" ]; then
    log "SI kernel still missing after a restore attempt; NOT retrying (see pacman output above in this log)."
    exit 1
fi

log "Stock kernel detected ($(uname -r)); reinstalling SI-enabled kernel."
touch "$MARKER"

steamos-readonly disable >> "$LOG" 2>&1
# Kernel package only (never headers: those need a pahole download and are
# irrelevant for booting; a network hiccup must not break the restore).
if pacman -U --noconfirm "$PKGDIR"/linux-neptune-616-6.16*-x86_64.pkg.tar.zst >> "$LOG" 2>&1; then
    steamos-readonly enable >> "$LOG" 2>&1
    log "Reinstall OK; rebooting into SI kernel."
    systemctl reboot
else
    steamos-readonly enable >> "$LOG" 2>&1
    log "pacman -U FAILED; not rebooting."
    exit 1
fi
