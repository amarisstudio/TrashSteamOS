#!/bin/bash
# Boot into Gaming Mode (gamescope session) from now on, and switch right now.
# The in-UI "Return to Gaming Mode" button fails silently on non-Deck hardware
# (steamos-session-select's privileged write never lands) — this does the same
# thing by hand. Requires amdgpu.dc=1 (atomic modesetting) — baked into this
# image's boot config. Run: sudo bash /opt/si-tools/enable-gaming-mode.sh
set -e
printf '[Autologin]\nUser=deck\nSession=gamescope-wayland.desktop\n' \
  > /etc/sddm.conf.d/zz-steamos-autologin.conf
echo "Gaming Mode set as boot session. Restarting display manager..."
systemctl restart sddm
