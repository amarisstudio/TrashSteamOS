# TrashSteamOS

**SteamOS 3.8 on the 2013 Mac Pro ("trash can"): custom SI-enabled kernel,
working display, Vulkan, and full Gaming Mode on GPUs Valve compiled out.**

<p align="center"><i>From</i> <code>amdgpu: amdgpu is built without SI support.</code> <i>to the Steam Deck UI on dual 2013 FirePro D300s.</i></p>

This repo has two audiences:

- **You want to run it.** Go to [Quick start](#quick-start). Flash the image,
  install, take the OTA update, done.
- **You want to see how it was done.** Read the [findings](#key-findings-the-hard-won-knowledge),
  the [chronicle](docs/trashcan-chronicle.md) (written as it happened, wrong
  turns included), and the git history. Nothing has been rewritten to look
  smarter in hindsight.

## Target hardware

| Component | Detail |
|---|---|
| Machine | Apple Mac Pro (Late 2013), "trash can" |
| GPUs | 2x AMD FirePro D300 (Pitcairn/Curacao XT, GCN 1.0 "Southern Islands", 2 GB, 1280 shaders each) |
| Display engine | DCE 6.0, running the modern amdgpu Display Core with `amdgpu.dc=1` (see findings) |
| Storage | Apple AHCI blade SSD, shows up as `/dev/sda`, not NVMe (several installer patches exist because of this) |
| Display out | HDMI port (internally DP-converted; enumerates as a DisplayPort connector) |
| OS | SteamOS 3.8 (holo/jupiter), kernel `linux-neptune-616` (6.16.12) |

The D700 and D500 variants are also GCN 1.0 (Tahiti) and should work with the
same kernel, but have not been tested. Reports welcome in Issues.

## Quick start

You need: a 2013 Mac Pro, a USB stick of 16 GB or more, a wired keyboard, a
display on the HDMI port, and a second computer to flash the stick.

1. **Download** the installer image from the
   [latest release](https://github.com/amarisstudio/TrashSteamOS/releases/latest).
   It is split into two parts because GitHub caps release files at 2 GB.
   Join them and check the hash:

   ```bash
   cat steamos-3.8.14-si-installer.img.xz.part-aa steamos-3.8.14-si-installer.img.xz.part-ab \
       > steamos-3.8.14-si-installer.img.xz
   shasum -a 256 -c SHA256SUMS --ignore-missing
   ```

2. **Flash** the `.img.xz` with balenaEtcher (it decompresses xz itself), or:

   ```bash
   xz -d steamos-3.8.14-si-installer.img.xz
   sudo dd if=steamos-3.8.14-si-installer.img of=/dev/rdiskN bs=4m status=progress
   ```

3. **Boot** the Mac Pro from the stick: hold Option at the chime and pick the
   EFI USB entry. You get a verbose boot and then the SteamOS repair desktop.
   The GRUB menu will not render on Apple EFI, that is expected.

4. **Install** to the internal SSD. This wipes it. From a terminal on the
   repair desktop (or Ctrl+Alt+F3 for a text console, user `deck`):

   ```bash
   cd ~/tools
   sudo DISK=/dev/sda DISK_SUFFIX= NOPROMPT=1 ./repair_device.sh all
   ```

   Check `lsblk` first if you are not sure the SSD is `/dev/sda`.

5. **First boot and the golden path.** Remove the stick, boot, connect to the
   network, then take the SteamOS update straight away:

   ```bash
   sudo steamos-readonly disable
   sudo pacman-key --init && sudo pacman-key --populate
   sudo steamos-readonly enable
   sudo steamos-update
   ```

   You land on genuine Valve SteamOS with the SI kernel and every fix carried
   across automatically. See [INSTALL.md](artifacts/INSTALL.md) for why this
   matters and for the manual kernel-only install path.

6. **Gaming Mode.** See [the next section](#gaming-mode).

## Gaming Mode

Gaming Mode (the Steam Deck UI, gamescope) works on this hardware, but two
things have to be true and one Deck feature does not work:

- **`amdgpu.dc=1` must be on the kernel command line.** On Southern Islands the
  modern Display Core is opt-in and the default legacy path has no atomic
  modesetting, which gamescope hard-requires. The image sets this on every boot
  entry and in `/etc/default/grub` (keep-listed, so it survives updates). If
  Gaming Mode ever shows a black screen or drops you back to desktop, check
  `cat /proc/cmdline | grep -o amdgpu.dc=1` first.
- **Steam must be the real client, not the OOBE one.** The recovery image ships
  `steam-jupiter-oobe`, whose launcher wipes the entire Steam install on every
  launch. The image patches this, but the proper fix is the OTA update (or
  `pacman -S steam-jupiter-stable`) in step 5 above. If you skip it you will see
  endless client re-updates and re-logins.
- **The in-UI session switch buttons do nothing on this machine.** "Switch to
  Desktop" in Gaming Mode and "Return to Gaming Mode" on the desktop fail
  silently. It is a polkit rule that only matches Deck hardware. Use the
  baked-in scripts instead:

  ```bash
  sudo bash /opt/si-tools/enable-gaming-mode.sh    # boot into Gaming Mode from now on, and switch now
  sudo bash /opt/si-tools/disable-gaming-mode.sh   # back to the Plasma X11 desktop
  ```

Once in Gaming Mode everything else is stock: Store, Library, Proton, the
on-screen keyboard, controller pairing.

## Known issues

- **Session switch buttons are broken** (above). Workaround: the two scripts in
  `/opt/si-tools/`. A proper polkit rule is the main open item.
- **The GRUB menu never renders on Apple EFI.** gfxterm does not work here.
  Every boot config change has to be made by editing files, not from the menu.
  The image sets a 5 second timeout anyway so an ESC or arrow key can still
  interrupt, blind.
- **Desktop session is Plasma X11, not Wayland.** `kwin_wayland` picks the
  wrong GPU on this dual-GPU machine and you get a black screen. X11 handles
  multi-GPU correctly. Do not switch the SDDM session to `plasma.desktop`.
- **Keep Valve's `amd_iommu=off` on the kernel line.** One experiment that
  dropped it hard-hung the machine. The image leaves Valve's stock flags alone.
- **Steam's desktop client renders its web views in software** on GFX6 (its own
  Chromium blocklist). It works, it is just slower. On the OOBE build the
  Store and Community tabs were visibly broken; that was the launcher bug, not
  the GPU, and it is fine after the OTA.
- **DX12 titles will not run.** vkd3d needs features GFX6 does not have. DX9,
  DX10 and DX11 via DXVK are fine. Vulkan 1.3 is exposed on both GPUs.
- **A SteamOS update that moves to a new kernel major** (linux-neptune-618 is
  already in Valve's tree) will need a rebuilt kernel. The self-heal service
  will still put 6.16 back and it normally still boots, but treat "an update
  happened" as your cue to rebuild. See [kernel-build/README.md](kernel-build/README.md).
- **The second GPU is headless.** `Cannot find any crtc` for the card without
  the display attached is benign. So is `PITCAIRN not supported in kfd`.
- **Only the D300 is tested.** D500 and D700 are the same GPU generation and
  should work; nobody has confirmed it yet.

## The problem

Valve compiles Southern Islands (GCN 1.0) support out of the Deck kernel
(`CONFIG_DRM_AMDGPU_SI is not set`) because the Deck is RDNA2. On SI hardware
no driver binds the GPUs: no display, no Vulkan, no OpenGL. The runtime flag
`amdgpu.si_support=1` cannot help, the code is absent from the binary.

## What this repo builds

1. **A custom `linux-neptune-616` kernel.** Valve's exact source
   (`github.com/evlaV/linux-integration` at `6.16.12-valve27`) and exact config,
   with a **three-line effective diff**: `CONFIG_DRM_AMDGPU_SI=y`,
   `CONFIG_DRM_AMDGPU_CIK=y`, and the dependency-driven `CONFIG_DRM_AMD_DC_SI=y`.
   Built via `makepkg` in a Docker `linux/amd64` container (Rosetta on Apple
   Silicon works; about 2.5 hours at `-j10` on an M1 Max).
2. **A modified official installer image.** Valve's
   `steamdeck-oobe-repair-20260707.10-3.8.14` image with the kernel and every
   hardware and OOBE fix baked in. The recovery image dd's *its own rootfs* onto
   the target, so one modified image fixes both the live installer and every
   system it installs.

## Complete change list (image v3)

**Kernel and boot:**
- SI-enabled `linux-neptune-616` installed in the image rootfs (self-contained
  `.pkg.tar.zst`; also in the release for manual installs)
- `amdgpu.dc=1` on all boot entries and in `/etc/default/grub`. This is the
  Gaming Mode enabler (see findings below)
- `GRUB_TIMEOUT=5`, verbose boot (`loglevel=5`, no quiet/splash) on USB entries

**Update survival:**
- `si-kernel-restore.service` (keep-listed): if a SteamOS update boots a stock
  kernel, it reinstalls the SI kernel from `/home/deck/si-kernel/` (or
  bootstraps from `/opt/si-kernel/` on first boot) and reboots once.
  Loop-protected for headless safety
- Expanded atomic-update keep-list: `/etc/default/grub` and the SDDM session
  configs ride across OTA updates. That is what makes "install, then take the
  OTA immediately" the recommended flow

**OOBE-image landmines defused** (the recovery rootfs was never meant to be a
daily driver):
- `steam-jupiter-oobe`'s launcher deletes the entire Steam install on every
  launch by design. Patched to persistent stable behavior; the OTA (or
  `pacman -S steam-jupiter-stable`) supersedes it properly
- SDDM autologin targets user `steamos`, which does not exist (uid 1000 is
  `deck`). Presents as an unrecoverable black screen at session start. Fixed
  with a drop-in (`User=deck`)
- Session set to Plasma X11 (see known issues)
- pacman keyring ships uninitialized (documented; init is one command)

**Installer script (`repair_device.sh`) hardening for non-Deck hardware:**
- `DISK`/`DISK_SUFFIX` env-overridable: `sudo DISK=/dev/sda DISK_SUFFIX= ./repair_device.sh all`
- NVMe sanitize skipped on non-NVMe targets
- Text-prompt fallback when zenity has no display (`NOPROMPT=1` also works)
- Auto-unmount of target partitions the desktop automounter grabbed

**Quality of life:**
- `/opt/si-tools/` on installed systems: `enable-gaming-mode.sh`,
  `disable-gaming-mode.sh`, plus the diagnostic helpers used during bring-up

## Key findings (the hard-won knowledge)

1. **`amdgpu.dc=1` is the whole ballgame for Gaming Mode.** On SI hardware the
   modern Display Core is *opt-in* (default is the legacy path). Legacy has no
   atomic modesetting; gamescope refuses to run without it. DC initializes
   cleanly on DCE 6.0 (`Display Core v3.2.334 initialized on DCE 6.0`). The
   community folklore that DC must be disabled on SI (`dc=0`) is, at least on
   this hardware and kernel, wrong in both directions: `dc=0` is a no-op
   (already the default), and `dc=1` works and unlocks the full Deck UI.
2. **The atomic-update keep-list only preserves `/etc`.** A kernel cannot be
   keep-listed; hence the self-heal service plus `/home` staging design.
3. **The evlaV mirror moved**: `gitlab.com/evlaV` is dead (final commit "the
   beginning of the end"); the live mirror is `github.com/evlaV/jupiter`
   (branch `3.8`) and `github.com/evlaV/linux-integration`.
4. **RADV works on GCN 1.0**: both D300s expose Vulkan 1.3 (`RADV PITCAIRN`),
   enough for DXVK 2.x and Proton. DX12 (vkd3d) is not viable on GFX6.
5. **The scariest bugs were not GPU bugs.** The "unrecoverable black screen at
   desktop start" was SDDM autologging into a user that does not exist. The
   "Steam is broken on this GPU" was a launcher that wipes Steam every boot.
   Both shipped in Valve's recovery image, which was never meant to be a daily
   driver.

## Repo layout

```
kernel-build/           Dockerfile, PKGBUILD, configs, and a README on how to rebuild the kernel
scripts/                build-installer-image.sh: produces the flashable image from Valve's pristine one
artifacts/              install scripts, self-heal unit, helper tools, INSTALL.md
                        (the built .img and .pkg.tar.zst binaries are on the GitHub release, not in git)
docs/trashcan-chronicle.md   The full story, written as it happened
docs/superpowers/       The original implementation plan, with notes on what broke and how it was fixed
```

## Reproducing from source

You do not need to do this to run it; the release has everything built. This is
for the curious, and for whoever rebuilds when Valve bumps the kernel major.

What it costs:

- Docker (Docker Desktop on macOS or Windows, or plain Docker on Linux) able to
  run `linux/amd64` containers, some of them privileged. Apple Silicon works via
  Rosetta.
- About 10 GB of downloads: roughly 4 GB of kernel git history from the evlaV
  mirror, Valve's 2 GB compressed recovery image, and the Arch build image.
- About 40 GB of free disk: the kernel source and objects are close to 30 GB,
  the pristine and patched images are 8 GB each.
- Time: roughly 2.5 hours for the kernel on an M1 Max under emulation, less on
  native x86_64. The image build is a few minutes.
- The Docker VM needs at least 8 GB of RAM for the kernel build.

Steps:

1. Build the kernel: see [kernel-build/README.md](kernel-build/README.md).
   Docker, `linux/amd64`, expect hours under emulation. Verify
   `CONFIG_DRM_AMDGPU_SI=y` in the final `.config` before compiling; configs
   silently drop options with unmet dependencies.
2. Fetch Valve's `steamdeck-oobe-repair-20260707.10-3.8.14.img.bz2` from
   `https://steamdeck-images.steamos.cloud/recovery/`, decompress it into
   `artifacts/`.
3. Run `scripts/build-installer-image.sh` (Docker required; the script finds
   its own paths, override `PRISTINE=` if the image lives elsewhere).
4. Flash and install as in the quick start.

## Status

Everything works: boot, display (Display Core on DCE 6.0), desktop (Plasma
X11), Vulkan on both GPUs, Steam client including Store, Big Picture, and
Gaming Mode (gamescope embedded session). The one open item is the polkit rule
for the in-UI session switch buttons. The test machine has since taken Valve's OTA
to 3.8.16 and kept working, which is the whole point of the design.

## License

MIT for the scripts and documentation in this repo. The kernel packaging under
`kernel-build/` derives from Valve's, Arch's and the Linux kernel's own files
and is GPL-2.0-only. See [LICENSE](LICENSE).

## Credits

- Valve, for SteamOS and for leaving the sources findable
- the evlaV mirror maintainer(s), "dedicated to the memory of Aaron Swartz"
- V10lator's linux-charcoal, proof the kernel build path works, and the C23
  libbpf patch pointer
- Built over three days of collaborative archaeology between a human with a
  screwdriver and USB sticks, and Claude doing the reading.
