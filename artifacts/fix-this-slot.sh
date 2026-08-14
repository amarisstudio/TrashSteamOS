#!/bin/bash
# Installs the SI kernel + self-heal onto the CURRENT (genuine SteamOS) slot.
# Run as: curl -s http://192.168.86.21:8765/fix-this-slot.sh | sudo bash
set -euo pipefail
MAC=http://192.168.86.21:8765

echo "==> Fetching SI kernel package from the Mac"
cd /home/deck
mkdir -p si-kernel
curl -sf -o si-kernel/linux-neptune-616-6.16.12.valve27-2.1-x86_64.pkg.tar.zst \
  "$MAC/linux-neptune-616-6.16.12.valve27-2.1-x86_64.pkg.tar.zst"
curl -sf -o si-kernel/restore-si-kernel.sh "$MAC/restore-si-kernel.sh"
chmod +x si-kernel/restore-si-kernel.sh
chown -R deck:deck si-kernel

echo "==> Installing kernel (this replaces the stock valve24.5 kernel on THIS slot)"
steamos-readonly disable
pacman -U --noconfirm /home/deck/si-kernel/linux-neptune-616-*.pkg.tar.zst

echo "==> Installing self-heal service + keep-list on this slot"
curl -sf -o /etc/systemd/system/si-kernel-restore.service "$MAC/si-kernel-restore.service"
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
echo "==> DONE. Rebooting in 5 seconds — display should return on the SI kernel."
sleep 5
reboot
