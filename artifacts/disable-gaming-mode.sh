#!/bin/bash
# Return to the Plasma X11 desktop as the boot session, and switch right now.
# Counterpart of enable-gaming-mode.sh. The in-UI "Switch to Desktop" button
# has the same silent-failure problem on non-Deck hardware.
# Run: sudo bash /opt/si-tools/disable-gaming-mode.sh
set -e
rm -f /etc/sddm.conf.d/zz-steamos-autologin.conf
echo "Desktop (Plasma X11) restored as boot session. Restarting display manager..."
systemctl restart sddm
