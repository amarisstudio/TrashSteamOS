#!/bin/bash
# Makes amdgpu.dc=1 permanent: /etc/default/grub (keep-listed) + regenerate.
# Run: sudo bash make-dc1-permanent.sh
set -e
GD=/etc/default/grub
grep -q 'amdgpu\.dc=1' "$GD" || sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="amdgpu.dc=1 /' "$GD"
echo "--- $GD now: ---"
grep '^GRUB_CMDLINE_LINUX_DEFAULT' "$GD"
update-grub >/dev/null 2>&1 || update-grub
echo "--- regenerated grub.cfg dc=1 count: $(grep -c 'amdgpu.dc=1' /efi/EFI/steamos/grub.cfg) ---"
