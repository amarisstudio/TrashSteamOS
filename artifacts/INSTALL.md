# Installing the SI-enabled kernel on the SteamOS 3.8 Mac Pro

This covers the kernel-only install onto an existing SteamOS system, the
fresh-install path with the custom image, and how updates are survived.

The binaries (kernel packages and the installer image) are on the
[GitHub release](https://github.com/amarisstudio/TrashSteamOS/releases/latest).
Put them together with the scripts from this `artifacts/` folder on a USB stick.

## What you're installing

`linux-neptune-616 6.16.12.valve27-2.1` rebuilt from Valve's exact source and
config with two changes: `CONFIG_DRM_AMDGPU_SI=y` and `CONFIG_DRM_AMDGPU_CIK=y`
(plus `CONFIG_DRM_AMD_DC_SI=y`, which follows automatically from Arch's base
config once SI is allowed). Same pkgver/pkgrel as stock, so pacman treats it as
a reinstall of the package you already have.

## Quick install (recommended)

Plug the stick into the SteamOS machine, then from a console (Ctrl+Alt+F3 gets
you a text console if you have no display in the session; log in as `deck`):

```bash
cd /run/media/deck/<YOUR_USB_LABEL>/artifacts   # adjust path
sudo bash install-si-kernel.sh
sudo reboot
```

The script does, in order: stage packages in `/home/deck/si-kernel/`,
`steamos-readonly disable`, `pacman -U` both packages, install + enable the
self-heal service, write `/etc/atomic-update.conf.d/si-kernel.conf`,
`steamos-readonly enable`.

## Manual install (what the script does)

```bash
sudo steamos-readonly disable
sudo pacman -U linux-neptune-616-6.16.12.valve27-2.1-x86_64.pkg.tar.zst
sudo steamos-readonly enable
sudo reboot
```

The `-headers` package is on the stick too but is intentionally NOT installed:
it's only needed for building out-of-tree (DKMS) modules and it pulls in
`pahole` from the network. If you ever need it:
`sudo pacman -U linux-neptune-616-headers-*.pkg.tar.zst` (with network up).

Notes:
- pacman will say **"reinstalling linux-neptune-616"**. Expected: the version
  string matches stock.
- mkinitcpio may print `==> ERROR: module not found: ...` for a few modules.
  Known harmless on SteamOS custom kernel installs.
- The pacman hooks rebuild the initramfs and update the boot entries for you;
  no manual bootctl/grub work is needed.

## Verify after reboot

```bash
zcat /proc/config.gz | grep -E 'DRM_AMDGPU_(SI|CIK)|DRM_AMD_DC_SI'
# expect: CONFIG_DRM_AMDGPU_SI=y, CONFIG_DRM_AMDGPU_CIK=y, CONFIG_DRM_AMD_DC_SI=y
sudo dmesg | grep -iE 'amdgpu.*(si_support|initialized|firepro|pitcairn|curacao)'
lspci -k | grep -A3 VGA   # both D300s should show 'Kernel driver in use: amdgpu'
```

No `amdgpu.si_support=1` cmdline flag is needed: radeon is not built, so
si_support/cik_support default to 1 in this configuration.

## Surviving SteamOS updates. Read this, it matters

**The obvious approach, keep-listing the kernel in
`/etc/atomic-update.conf.d/`, does not work.** The actual implementation in
Valve's `steamos-customizations` (rauc/atomic-update-keep.conf plus
post-install.sh) only preserves paths under **/etc**. A SteamOS update
writes a complete new rootfs image to the other A/B slot, kernel included.
`/usr/lib/modules` and the boot files are replaced wholesale and no conf file
can exempt them. (The linux-charcoal project hit the same wall; their answer
is "reinstall after every update".)

So instead this install sets up a **self-healing loop** out of the pieces that
*do* survive updates:

- `/home` persists → the kernel packages and `restore-si-kernel.sh` are staged
  in `/home/deck/si-kernel/`.
- `/etc/systemd/system/*.service` and its `.wants/` symlink are on the default
  keep-list (and pinned again by our drop-in) → `si-kernel-restore.service`
  survives into the updated slot.
- On every boot the service checks `/proc/config.gz`; if the running kernel
  lacks `CONFIG_DRM_AMDGPU_SI`, it reinstalls the packages from /home and
  reboots once. A marker file prevents reboot loops if the reinstall fails.

Net effect: after a SteamOS update the machine boots once with no display
(stock kernel), silently reinstalls the SI kernel, reboots itself, and comes
back with working graphics. No keyboard required.

**Caveat:** if a future SteamOS update jumps to a new kernel major
(linux-neptune-618 is already in Valve's tree), the reinstalled 6.16 package
may not match the new OS image and the safe thing is to rebuild against the
new source. The restore service will still put 6.16 back and it will normally
still boot, but treat "an update happened" as your cue to rebuild.

## The custom installer image (fresh installs)

`steamos-3.8.14-si-installer.img.xz` (on the release, split into two parts;
see the README quick start for joining and verifying) is Valve's official
`steamdeck-oobe-repair-20260707.10-3.8.14` image with the SI kernel installed
into its rootfs, the self-heal service pre-wired, and one quality-of-life
patch. Because the installer literally copies its own rootfs onto the target
disk, both the *live installer* and *every system it installs* boot the SI
kernel. No post-install kernel swap needed.

Flash it:

```bash
# balenaEtcher: pick the .img.xz directly. Or dd (find the right disk with diskutil list):
xz -d steamos-3.8.14-si-installer.img.xz
sudo dd if=steamos-3.8.14-si-installer.img of=/dev/rdiskN bs=4m status=progress
```

On the trash can, boot from USB (hold Option at the chime, pick the EFI USB
entry). To reimage the internal disk (**this wipes it**):

```bash
cd ~/tools
# Stock scripts assume a Steam Deck NVMe (/dev/nvme0n1). The 2013 Mac Pro's
# SSD is AHCI, usually /dev/sda with no 'p' partition suffix. The image is
# patched to accept overrides (check your disk with lsblk first):
sudo DISK=/dev/sda DISK_SUFFIX= ./repair_device.sh all
```

Verify the download if in doubt: `shasum -a 256 -c SHA256SUMS --ignore-missing`

## After a fresh install from the custom image: fix the Steam launcher properly

The recovery image (and therefore any dd-based install from it) ships
`steam-jupiter-oobe`, whose launcher wipes the entire Steam install on every
launch. The image patches the launcher to stop the bleeding, but the proper
fix is installing Valve's real package (needs network; the keyring init is
one-time; recovery images ship it uninitialized):

```bash
sudo steamos-readonly disable
sudo pacman-key --init && sudo pacman-key --populate
sudo pacman -S steam-jupiter-stable    # 'y' to removing steam-jupiter-oobe
sudo steamos-readonly enable
```

## Image v3 notes: Gaming Mode and the golden path

- The image boots with **`amdgpu.dc=1`** everywhere: Display Core runs on
  DCE 6.0 and provides atomic modesetting, so **Gaming Mode (gamescope) works**.
  (Historic note: earlier revisions used `dc=0`. It turned out to be a no-op;
  legacy was the default all along, and DC actually works. See README findings.)
- Desktop session is **Plasma X11** (Wayland's compositor picks the wrong GPU
  on the dual-D300 Mac Pro).
- The in-Steam "Return to Gaming Mode"/"Switch to Desktop" buttons fail
  silently on non-Deck hardware (polkit). Use the baked-in tools instead:
  `sudo bash /opt/si-tools/enable-gaming-mode.sh` (boot-to-Deck-UI) and
  `sudo bash /opt/si-tools/disable-gaming-mode.sh` (back to desktop).
- **Golden path after a fresh install:** boot → connect network →
  `sudo steamos-readonly disable && sudo pacman-key --init && sudo pacman-key --populate && sudo steamos-readonly enable`
  → take the SteamOS OTA update (Settings → System, or `sudo steamos-update`).
  You land on genuine Valve SteamOS with the SI kernel (self-heal) and all
  configs (keep-list) carried across automatically. The best end state.

## Uninstall / rollback

```bash
sudo systemctl disable si-kernel-restore.service
sudo rm -f /etc/systemd/system/si-kernel-restore.service \
           /etc/atomic-update.conf.d/si-kernel.conf
sudo rm -rf /home/deck/si-kernel
```

Then either reinstall the stock package or simply take the next SteamOS
update, which restores a stock rootfs.
