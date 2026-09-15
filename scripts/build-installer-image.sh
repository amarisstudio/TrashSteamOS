#!/bin/bash
# Builds the SI-enabled SteamOS 3.8.14 installer image.
#
# Takes the pristine steamdeck-oobe-repair image, installs the SI-enabled
# linux-neptune-616 packages into its rootfs (which is both the live installer
# system AND the payload dd'd onto the target disk), wires up the self-heal
# service, and patches repair_device.sh so the target disk is overridable for
# non-Deck hardware (2013 Mac Pro: sudo DISK=/dev/sda DISK_SUFFIX= ...).
#
# Image v2 additions (2013 Mac Pro / AMD FirePro D300, GCN 1.0):
#   - EFI grub.cfg: timeout=5 (re-set after steamenv_init), verbose boot
#     (loglevel=5, no quiet/splash), amdgpu.dc=0 and console-first
#     multi-user.target on the USB kernel lines (both env-toggleable, below).
#   - rootfs /etc/default/grub: amdgpu.dc=0 in GRUB_CMDLINE_LINUX_DEFAULT and
#     GRUB_TIMEOUT=5, so grub-mkconfig on the INSTALLED system inherits them.
#   - repair_device.sh: skip nvme sanitize on non-NVMe disks, text-prompt
#     fallback when zenity/DISPLAY is unavailable, and pre-unmount of
#     auto-mounted target partitions before sfdisk.
#
# Image v3 corrections (2026-08-14, after full bring-up on the Mac Pro):
#   - amdgpu.dc=1 (NOT dc=0): DC display core is OPT-IN on SI hardware and
#     works on DCE 6.0. It enables atomic modesetting, which gamescope
#     (Gaming Mode) requires. dc=0 was never load-bearing.
#   - SDDM session: plasmax11.desktop. kwin_wayland picks the wrong GPU on
#     the dual-D300 Mac Pro (black screen); Plasma X11 handles multi-GPU.
#   - Keep-list expanded so a post-install OTA to genuine SteamOS preserves
#     the whole configuration (recommended flow: install -> OTA immediately).
#   - Helper scripts baked into /opt/si-tools/ on the installed system.
#
# Run on the macOS host. Requires: Docker Desktop running, kernel packages
# already present in artifacts/.
set -euo pipefail

PROJ=$(cd "$(dirname "$0")/.." && pwd)
# Valve's pristine recovery image, decompressed (.img, not .img.bz2). Download
# from https://steamdeck-images.steamos.cloud/recovery/ and bunzip2 it.
# Override with PRISTINE=/path/to/image.img if it lives elsewhere.
PRISTINE=${PRISTINE:-$PROJ/artifacts/steamdeck-oobe-repair-20260707.10-3.8.14.img}
OUT=${OUT:-$PROJ/artifacts/steamos-3.8.14-si-installer.img}
[ -f "$PRISTINE" ] || { echo "ERROR: pristine image not found at $PRISTINE"; exit 1; }

# Partition offsets (sectors, from the GPT of the pristine image)
ROOT_OFF=$((655360*512)); ROOT_SIZE=$((10485760*512))
HOME_OFF=$((11665408*512)); HOME_SIZE=$((4194271*512))
EFI_OFF=$((131072*512)); EFI_SIZE=$((262144*512))

# Image v3 toggles (set to 0 to disable)
SI_DC1=${SI_DC1:-1}                        # append amdgpu.dc=1 (enable DC display core on DCE6;
                                           # required for atomic modesetting / gamescope / Gaming Mode)
                                           # in EFI grub.cfg AND rootfs /etc/default/grub
# Default 0 since the SDDM ghost-user autologin fix landed (the graphical repair
# desktop works on GFX6); set to 1 to force console-only USB boots for debugging.
USB_CONSOLE_FIRST=${USB_CONSOLE_FIRST:-0}

ls "$PROJ"/artifacts/linux-neptune-616-6.16*-x86_64.pkg.tar.zst >/dev/null

echo "==> Copying pristine image to $OUT (7.6G, takes a minute)"
cp "$PRISTINE" "$OUT"

echo "==> Installing kernel + self-heal into image rootfs (privileged container)"
docker run -i --rm --privileged --platform linux/amd64 -u 0 \
  -v "$PROJ/artifacts":/a -v "$(dirname "$OUT")":/outdir \
  -e IMG="/outdir/$(basename "$OUT")" -e ROOT_OFF=$ROOT_OFF -e ROOT_SIZE=$ROOT_SIZE \
  -e SI_DC1="$SI_DC1" \
  neptune-kernel-build bash -s <<'CONTAINER'
set -euo pipefail
pacman -Sy --noconfirm --needed btrfs-progs > /dev/null
mkdir -p /mnt/root
mount -o loop,offset=$ROOT_OFF,sizelimit=$ROOT_SIZE "$IMG" /mnt/root

# SteamOS rootfs is btrfs with the read-only property set (what
# steamos-readonly toggles on-device). Clear it while we work.
btrfs property set /mnt/root ro false

# Stage packages + restore script on the image rootfs (survives the dd to
# target; /opt is the bootstrap source for /home staging on first boot)
# Kernel package only. The headers package depends on pahole, which would
# need a network fetch (unavailable in this chroot, and undesirable for the
# offline self-heal path). Headers are only for DKMS and stay on the USB.
mkdir -p /mnt/root/opt/si-kernel
cp /a/linux-neptune-616-6.16*-x86_64.pkg.tar.zst /a/restore-si-kernel.sh /mnt/root/opt/si-kernel/
chmod +x /mnt/root/opt/si-kernel/restore-si-kernel.sh

# Install the kernel with the image's own pacman (hooks regenerate the
# initramfs and refresh /boot, which GRUB boots from)
mount -t proc proc /mnt/root/proc
mount -t sysfs sys /mnt/root/sys
mount --bind /dev /mnt/root/dev
mount -t tmpfs tmpfs /mnt/root/run
chroot /mnt/root bash -c 'pacman -U --noconfirm /opt/si-kernel/linux-neptune-616-6.16*-x86_64.pkg.tar.zst'
umount /mnt/root/proc /mnt/root/sys /mnt/root/dev /mnt/root/run

# Self-heal service, enabled, plus keep-list pin
cp /a/si-kernel-restore.service /mnt/root/etc/systemd/system/
mkdir -p /mnt/root/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/si-kernel-restore.service \
      /mnt/root/etc/systemd/system/multi-user.target.wants/si-kernel-restore.service
# v3: expanded keep-list. After an OTA to genuine SteamOS, the new slot
# keeps the self-heal wiring, the display fix, and the session configs. This
# makes "install, then take the OTA immediately" the golden path: you end up
# on Valve's real OS with every fix carried across automatically.
mkdir -p /mnt/root/etc/atomic-update.conf.d
cat > /mnt/root/etc/atomic-update.conf.d/si-kernel.conf <<'EOF'
/etc/systemd/system/si-kernel-restore.service
/etc/systemd/system/multi-user.target.wants/si-kernel-restore.service
/etc/default/grub
/etc/sddm.conf.d/zz-si-autologin.conf
/etc/sddm.conf.d/zz-steamos-autologin.conf
EOF

# SDDM autologin fix (v2, session corrected in v3). The shipped config
# autologins user 'steamos', which does not exist on this image (uid 1000 is
# 'deck'). SDDM fails autologin and the greeter dies with it: unrecoverable
# black screen. v3: session is Plasma X11, NOT Wayland. kwin_wayland grabs
# the wrong GPU on the dual-D300 Mac Pro (verified 2026-08-14); X11 handles
# multi-GPU correctly. Drop-in sorts last, overrides the stock config.
mkdir -p /mnt/root/etc/sddm.conf.d
cat > /mnt/root/etc/sddm.conf.d/zz-si-autologin.conf <<'EOF'
[Autologin]
User=deck
Session=plasmax11.desktop
EOF

# v3: helper toolbox on the installed system (these were battle-tested over
# SSH during bring-up; paths inside them are device-local, no network needed)
mkdir -p /mnt/root/opt/si-tools
for t in steam-loop-tool.sh fix-keeplist.sh enable-gaming-mode.sh disable-gaming-mode.sh; do
  [ -f "/a/$t" ] && cp "/a/$t" /mnt/root/opt/si-tools/
done
chmod 755 /mnt/root/opt/si-tools/* 2>/dev/null || true
ls /mnt/root/opt/si-tools/

# Image v2: neuter the steam-jupiter-oobe launcher. The recovery image ships an
# OOBE /usr/bin/steam that rm -rf's the user's ENTIRE Steam install on every
# launch ("fresh steam per boot"). Fine on a repair stick, catastrophic on a
# dd-installed daily driver: endless client re-updates + login amnesia.
# Replace with the steam-jupiter-stable behavior (verified on-device
# 2026-08-14). Proper fix post-install: pacman -S steam-jupiter-stable
# (documented in INSTALL.md); this patch makes the interim behavior sane.
# /usr/bin/steam is a symlink to steam-jupiter in the image. Resolve it and
# patch the real file (leaving the symlink itself intact).
STEAMBIN=/mnt/root/usr/bin/steam
if [ -L "$STEAMBIN" ]; then STEAMBIN="/mnt/root$(readlink "$STEAMBIN")"; fi
cp "$STEAMBIN" "${STEAMBIN}.oobe-orig"
cat > "$STEAMBIN" <<'EOF'
#!/bin/bash
# Patched by SI installer build: steam-jupiter-oobe's wiping entrypoint
# replaced with persistent stable-style behavior. Original backed up next to
# this file as *.oobe-orig. Recommended: pacman -S steam-jupiter-stable.
set -euo pipefail
exec /usr/lib/steam/steam -steamdeck "$@"
EOF
chmod 755 "$STEAMBIN"
echo "patched launcher: $STEAMBIN (backup: ${STEAMBIN}.oobe-orig)"

# Image v2: GRUB defaults for the INSTALLED system. grub-mkconfig reads
# /etc/default/grub when the installed system regenerates its own boot config,
# so the amdgpu.dc=1 / timeout fixes survive past the USB installer's grub.cfg.
GRUBDEF=/mnt/root/etc/default/grub
if [[ "$SI_DC1" = 1 ]] && ! grep -q 'amdgpu\.dc=1' "$GRUBDEF"; then
  # Append inside the existing quotes (stock Arch/SteamOS format keeps the
  # value single- or double-quoted; preserve existing contents).
  sed -i "s/^\(GRUB_CMDLINE_LINUX_DEFAULT=.*\)\([\"']\)[[:space:]]*\$/\1 amdgpu.dc=1\2/" "$GRUBDEF"
  grep -q 'amdgpu\.dc=1' "$GRUBDEF" || { echo "ERROR: could not append amdgpu.dc=1 to GRUB_CMDLINE_LINUX_DEFAULT in $GRUBDEF"; exit 1; }
fi
if grep -q '^GRUB_TIMEOUT=' "$GRUBDEF"; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' "$GRUBDEF"
else
  echo 'GRUB_TIMEOUT=5' >> "$GRUBDEF"
fi
echo "== /etc/default/grub after image v3 patch =="
grep -E '^(GRUB_TIMEOUT|GRUB_CMDLINE_LINUX_DEFAULT)=' "$GRUBDEF"

# PENDING DIAGNOSIS. Deliberately DISABLED: console-first default for the
# INSTALLED system (not just the USB). Uncomment only once GPU bring-up on the
# FirePro D300 has been diagnosed and a console-first install is the decision:
# ln -sf /usr/lib/systemd/system/multi-user.target /mnt/root/etc/systemd/system/default.target

echo "== verification =="
ls /mnt/root/usr/lib/modules/
ls -lh /mnt/root/boot/vmlinuz-linux-neptune-616 /mnt/root/boot/initramfs-linux-neptune-616.img
# Extract the embedded IKCONFIG from the new kernel and prove SI is in it
chroot /mnt/root bash -c 'M=$(ls -d /usr/lib/modules/*neptune-616* | head -1);
  /usr/lib/modules/*/build/scripts/extract-ikconfig $M/vmlinuz 2>/dev/null ||
  true' | grep -E "CONFIG_DRM_AMDGPU_(SI|CIK)=|CONFIG_DRM_AMD_DC_SI=" || \
  echo "WARNING: could not extract ikconfig for verification"

# Restore stock read-only posture
btrfs property set /mnt/root ro true
umount /mnt/root
CONTAINER

echo "==> Patching EFI grub.cfg (timeout=5, verbose boot, amdgpu.dc=1)"
docker run -i --rm --privileged -v "$(dirname "$OUT")":/outdir \
  -e IMG="/outdir/$(basename "$OUT")" -e EFI_OFF=$EFI_OFF -e EFI_SIZE=$EFI_SIZE \
  -e SI_DC1="$SI_DC1" -e USB_CONSOLE_FIRST="$USB_CONSOLE_FIRST" \
  alpine sh -s <<'CONTAINER'
set -eu
apk add --quiet util-linux python3
losetup -o $EFI_OFF --sizelimit $EFI_SIZE /dev/loop7 "$IMG"
mkdir -p /mnt/efi
mount -t vfat /dev/loop7 /mnt/efi
python3 - <<'PY'
import os, re

path = "/mnt/efi/EFI/steamos/grub.cfg"
dc1 = os.environ.get("SI_DC1", "1") == "1"
console_first = os.environ.get("USB_CONSOLE_FIRST", "1") == "1"
QUIET_TAIL = " loglevel=3 quiet splash plymouth.ignore-serial-consoles"

with open(path) as f:
    lines = f.read().splitlines()

out = []
timeouts = kernels = inits = 0
for line in lines:
    s = line.strip()
    # (a) header timeout=0 -> timeout=5 (matches both "timeout=0" and "set timeout=0";
    # deliberately does NOT match timeout_style= or cmdline *_timeout= values)
    if re.fullmatch(r"(set\s+)?timeout=0", s):
        line = line.replace("timeout=0", "timeout=5")
        timeouts += 1
    # (b)(c)(d) kernel cmdline edits on every steamenv_boot linux line
    if "steamenv_boot" in line and "vmlinuz-linux-neptune" in line:
        if QUIET_TAIL not in line:
            raise SystemExit("unexpected kernel cmdline (quiet/splash tail missing): " + line)
        line = line.replace(QUIET_TAIL, " loglevel=5")
        if dc1:
            line += " amdgpu.dc=1"
        if console_first:
            line += " systemd.unit=multi-user.target"
        kernels += 1
    out.append(line)
    # (a) steamenv_init is believed to reset timeout -> force it back afterwards
    if s == "steamenv_init" or s.startswith("steamenv_init "):
        out.append("set timeout=5")
        inits += 1

if timeouts < 1:
    raise SystemExit("did not find a timeout=0 line to patch")
if inits != 1:
    raise SystemExit("expected exactly 1 steamenv_init line, found %d" % inits)
if kernels != 3:
    raise SystemExit("expected 3 steamenv_boot kernel lines, found %d" % kernels)

with open(path, "w") as f:
    f.write("\n".join(out) + "\n")
print("grub.cfg patched: %d timeout line(s), timeout re-set after steamenv_init, %d kernel line(s)"
      % (timeouts, kernels))
PY
# (e) drop stale grub.cfg.new if present (grub.cfg.stock backup left untouched)
rm -f /mnt/efi/EFI/steamos/grub.cfg.new
echo "== grub.cfg after image v3 patch =="
grep -n "timeout=" /mnt/efi/EFI/steamos/grub.cfg
echo "amdgpu.dc=1 lines:              $(grep -c 'amdgpu.dc=1' /mnt/efi/EFI/steamos/grub.cfg || true)"
echo "multi-user.target lines:        $(grep -c 'systemd.unit=multi-user.target' /mnt/efi/EFI/steamos/grub.cfg || true)"
echo "loglevel=5 lines:               $(grep -c 'loglevel=5' /mnt/efi/EFI/steamos/grub.cfg || true)"
echo "residual quiet/splash lines:    $(grep -c 'quiet splash' /mnt/efi/EFI/steamos/grub.cfg || true)"
umount /mnt/efi
losetup -d /dev/loop7
CONTAINER

echo "==> Patching repair_device.sh on home partition (env-overridable DISK)"
docker run -i --rm --privileged -v "$(dirname "$OUT")":/outdir \
  -e IMG="/outdir/$(basename "$OUT")" -e HOME_OFF=$HOME_OFF -e HOME_SIZE=$HOME_SIZE \
  alpine sh -s <<'CONTAINER'
set -eu
# GNU sed (multi-line replacements) and bash (syntax check) on top of busybox
apk add --quiet util-linux e2fsprogs e2fsprogs-extra sed bash
losetup -o $HOME_OFF --sizelimit $HOME_SIZE /dev/loop6 "$IMG"
cd /tmp
debugfs -R "dump /deck/tools/repair_device.sh repair_device.sh" /dev/loop6
sed -i -e 's|^DISK=/dev/nvme0n1$|DISK=${DISK:-/dev/nvme0n1}|' \
       -e 's|^DISK_SUFFIX=p$|DISK_SUFFIX=${DISK_SUFFIX-p}|' repair_device.sh
grep -n "^DISK" repair_device.sh | head -3

# --- image v2 patches ---
# (a) all) case only: skip the NVMe-only sanitize on non-NVMe targets (the Mac
#     Pro disk is AHCI /dev/sda; nvme sanitize-log would fail). The sanitize)
#     verb's own call and the sanitize_all() definition are left untouched.
sed -i '/^all)$/,/^  ;;$/ s|^  sanitize_all$|  if [[ "$DISK" == *nvme* ]]; then sanitize_all; else echo "Skipping NVMe sanitize: $DISK is not NVMe"; fi|' repair_device.sh

# (b) prompt_step: text-prompt fallback when headless (no DISPLAY) or zenity is
#     unavailable. prompt_reboot delegates to prompt_step, so this covers both;
#     the NOPROMPT=1 early-return above the zenity call is untouched. zenity and
#     read stay inside condition lists so a "Cancel" exits cleanly instead of
#     tripping the script's ERR trap (which sleeps forever).
sed -i 's#^  zenity --title "$title" --question --ok-label "Proceed" --cancel-label "Cancel" --no-wrap --text "$msg"$#  if [[ -n ${DISPLAY:-} ]] \&\& command -v zenity >/dev/null 2>\&1; then\n    if ! zenity --title "$title" --question --ok-label "Proceed" --cancel-label "Cancel" --no-wrap --text "$msg"; then exit 1; fi\n  else\n    echo -e "$msg"\n    read -r -p "Proceed? [y/N] " _si_answer || exit 1\n    [[ ${_si_answer} == [Yy]* ]] || exit 1\n  fi#' repair_device.sh

# (c) all) case: unmount anything udisks auto-mounted from the target disk (and
#     disable swap) before sfdisk rewrites the partition table, deepest first.
sed -i 's#^  prompt_step "Wipe Device & Install SteamOS".*#&\n  for m in $(lsblk -nro MOUNTPOINTS "$DISK" | grep . | sort -r); do umount "$m" || exit 1; done\n  swapoff "$DISK"* 2>/dev/null || true#' repair_device.sh

echo "== repair_device.sh image v2 verification =="
grep -n 'Skipping NVMe sanitize' repair_device.sh
grep -n 'command -v zenity' repair_device.sh
grep -n 'read -r -p "Proceed' repair_device.sh
grep -n 'lsblk -nro MOUNTPOINTS' repair_device.sh
# exactly one bare "  sanitize_all" call must remain (the sanitize) verb's)
[ "$(grep -c '^  sanitize_all$' repair_device.sh)" = "1" ]
bash -n repair_device.sh
echo "bash -n: OK"

debugfs -w -R "rm /deck/tools/repair_device.sh" /dev/loop6
debugfs -w -R "write repair_device.sh /deck/tools/repair_device.sh" /dev/loop6
debugfs -w -R "sif /deck/tools/repair_device.sh mode 0100755" /dev/loop6
debugfs -w -R "sif /deck/tools/repair_device.sh uid 1000" /dev/loop6
debugfs -w -R "sif /deck/tools/repair_device.sh gid 1000" /dev/loop6
losetup -d /dev/loop6
CONTAINER

echo "==> SHA256"
shasum -a 256 "$OUT" | tee "$OUT.sha256"
echo "==> Done: $OUT"
