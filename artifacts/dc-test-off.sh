#!/bin/bash
# Reverts the dc=1 test: restores the pre-test grub.cfg backup.
# Run: curl -s http://192.168.86.21:8765/dc-test-off.sh | sudo bash
set -e
CFG=/efi/EFI/steamos/grub.cfg
[ -f "$CFG.pre-dc-test" ] || { echo "no backup found"; exit 1; }
cp "$CFG.pre-dc-test" "$CFG"
echo "reverted. dc=1 count now: $(grep -c 'amdgpu.dc=1' "$CFG" || true)"
