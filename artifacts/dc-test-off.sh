#!/bin/bash
# Reverts the dc=1 test: restores the pre-test grub.cfg backup.
# Run: sudo bash dc-test-off.sh
set -e
CFG=/efi/EFI/steamos/grub.cfg
[ -f "$CFG.pre-dc-test" ] || { echo "no backup found"; exit 1; }
cp "$CFG.pre-dc-test" "$CFG"
echo "reverted. dc=1 count now: $(grep -c 'amdgpu.dc=1' "$CFG" || true)"
