#!/bin/bash
# Prepares the internal disk's GRUB for the DC experiment: makes the boot menu
# actually appear (re-assert timeout after Valve's steamenv_init resets it).
# Run: sudo bash prep-dc-test.sh
set -e
CFG=/efi/EFI/steamos/grub.cfg
[ -f "$CFG" ] || { echo "ERROR: $CFG not found"; exit 1; }
cp -n "$CFG" "$CFG.bak" 2>/dev/null || true
COUNT=$(grep -c '^steamenv_init$' "$CFG")
if [ "$COUNT" != "1" ]; then echo "ERROR: expected exactly 1 steamenv_init line, found $COUNT. Aborting."; exit 1; fi
if grep -A1 '^steamenv_init$' "$CFG" | grep -q 'set timeout=5'; then
  echo "Already patched."
else
  sed -i '/^steamenv_init$/a set timeout=5' "$CFG"
  echo "Patched."
fi
echo "--- verification (steamenv_init and the line after it): ---"
grep -A1 '^steamenv_init$' "$CFG"
echo "--- kernel line count with dc=0 (for reference): ---"
grep -c 'amdgpu.dc=0' "$CFG"
