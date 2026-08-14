#!/bin/bash
# Adds amdgpu.dc=1 to every kernel line in the current slot's grub.cfg (with backup).
# Run: curl -s http://192.168.86.21:8765/dc-test-on.sh | sudo bash
set -e
CFG=/efi/EFI/steamos/grub.cfg
cp -n "$CFG" "$CFG.pre-dc-test"
if grep -q 'amdgpu.dc=1' "$CFG"; then
  echo "already on"
else
  sed -i '/steamenv_boot.*vmlinuz-linux-neptune-616 /s/$/ amdgpu.dc=1/' "$CFG"
fi
echo "dc=1 count: $(grep -c 'amdgpu.dc=1' "$CFG")"
