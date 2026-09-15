#!/bin/bash
# Installs the SI kernel + self-heal onto the CURRENT (genuine SteamOS) slot.
# Run from the artifacts/ folder on the USB stick (the kernel package,
# restore-si-kernel.sh and si-kernel-restore.service must sit next to it):
#   cd /run/media/deck/<USB_LABEL>/artifacts && sudo bash fix-this-slot.sh
set -euo pipefail
SRC=${SRC:-$(cd "$(dirname "$0")" && pwd)}

echo "==> Staging SI kernel package from $SRC"
cd /home/deck
mkdir -p si-kernel
cp "$SRC"/linux-neptune-616-6.16.12.valve27-2.1-x86_64.pkg.tar.zst si-kernel/
cp "$SRC"/restore-si-kernel.sh si-kernel/
chmod +x si-kernel/restore-si-kernel.sh
chown -R deck:deck si-kernel

echo "==> Installing kernel (this replaces the stock valve24.5 kernel on THIS slot)"
steamos-readonly disable
pacman -U --noconfirm /home/deck/si-kernel/linux-neptune-616-*.pkg.tar.zst

echo "==> Installing self-heal service + keep-list on this slot"
cp "$SRC"/si-kernel-restore.service /etc/systemd/system/si-kernel-restore.service
systemctl daemon-reload
systemctl enable si-kernel-restore.service
mkdir -p /etc/atomic-update.conf.d
cat > /etc/atomic-update.conf.d/si-kernel.conf <<'EOF'
/etc/systemd/system/si-kernel-restore.service
/etc/systemd/system/multi-user.target.wants/si-kernel-restore.service
/etc/default/grub
/etc/sddm.conf.d/zz-local.conf
EOF

echo "==> SDDM autologin fix (genuine OS may carry the ghost user too)"
mkdir -p /etc/sddm.conf.d
printf '[Autologin]\nUser=deck\nSession=plasma.desktop\n' > /etc/sddm.conf.d/zz-local.conf

steamos-readonly enable
echo "==> DONE. Rebooting in 5 seconds. Display should return on the SI kernel."
sleep 5
reboot
