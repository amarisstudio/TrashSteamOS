#!/bin/bash
# Adds the display-fix and session configs to the atomic-update keep-list.
# Run: sudo bash fix-keeplist.sh
set -e
CONF=/etc/atomic-update.conf.d/si-kernel.conf
grep -q "^/etc/default/grub$" "$CONF" 2>/dev/null || echo "/etc/default/grub" >> "$CONF"
grep -q "^/etc/sddm.conf.d/zz-local.conf$" "$CONF" 2>/dev/null || echo "/etc/sddm.conf.d/zz-local.conf" >> "$CONF"
echo "--- keep-list is now: ---"
cat "$CONF"
