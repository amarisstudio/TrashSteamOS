# TrashSteamOS

**SteamOS 3.8 on the 2013 Mac Pro ("trash can") — custom SI-enabled kernel,
working display, Vulkan, and full Gaming Mode on GPUs Valve compiled out.**

<p align="center"><i>From</i> <code>amdgpu: amdgpu is built without SI support.</code> <i>to the Steam Deck UI — on dual 2013 FirePro D300s.</i></p>

## Target hardware

| Component | Detail |
|---|---|
| Machine | Apple Mac Pro (Late 2013), "trash can" |
| GPUs | 2× AMD FirePro D300 — Pitcairn/Curacao XT, GCN 1.0 "Southern Islands", 2 GB, 1280 shaders each |
| Display engine | DCE 6.0 (runs the modern amdgpu Display Core with `amdgpu.dc=1` — see findings) |
| Storage | Apple AHCI blade SSD → `/dev/sda` (not NVMe — several installer patches exist because of this) |
| Display out | HDMI port (internally DP-converted; enumerates as a DisplayPort connector) |
| OS | SteamOS 3.8 (holo/jupiter), kernel `linux-neptune-616` (6.16.12) |

## The problem

Valve compiles Southern Islands (GCN 1.0) support out of the Deck kernel
(`CONFIG_DRM_AMDGPU_SI is not set`) because the Deck is RDNA2. On SI hardware
no driver binds the GPUs: no display, no Vulkan, no OpenGL. The runtime flag
`amdgpu.si_support=1` cannot help — the code is absent from the binary.

## What this repo builds

1. **A custom `linux-neptune-616` kernel** — Valve's exact source
   (`github.com/evlaV/linux-integration` @ `6.16.12-valve27`) and exact config,
   with a **three-line effective diff**: `CONFIG_DRM_AMDGPU_SI=y`,
   `CONFIG_DRM_AMDGPU_CIK=y`, and the dependency-driven `CONFIG_DRM_AMD_DC_SI=y`.
   Built via `makepkg` in a Docker `linux/amd64` container (Rosetta on Apple
   Silicon works; ~2.5 h at `-j10` on an M1 Max).
2. **A modified official installer image** — Valve's
   `steamdeck-oobe-repair-20260707.10-3.8.14` image with the kernel and every
   hardware/OOBE fix baked in. The recovery image dd's *its own rootfs* onto
   the target, so one modified image fixes both the live installer and every
   system it installs. Flash with balenaEtcher or `dd`.

## Complete change list (image v3)

**Kernel/boot:**
- SI-enabled `linux-neptune-616` installed in the image rootfs (self-contained
  `.pkg.tar.zst`; also in `artifacts/` for manual installs)
- `amdgpu.dc=1` on all boot entries and in `/etc/default/grub` — **the Gaming
  Mode enabler** (see findings below)
- `GRUB_TIMEOUT=5`, verbose boot (`loglevel=5`, no quiet/splash) on USB entries
- Note: the GRUB menu **never renders on Apple EFI** (gfxterm) — edit configs,
  don't rely on the menu

**Update survival:**
- `si-kernel-restore.service` (keep-listed): if a SteamOS update boots a stock
  kernel, it reinstalls the SI kernel from `/home/deck/si-kernel/` (or
  bootstraps from `/opt/si-kernel/` on first boot) and reboots once —
  loop-protected for headless safety
- Expanded atomic-update keep-list: `/etc/default/grub` and the SDDM session
  configs ride across OTA updates. **Recommended flow: install → boot →
  `pacman-key --init && pacman-key --populate` → take the OTA immediately** —
  you land on genuine SteamOS with every fix carried across automatically.

**OOBE-image landmines defused** (the recovery rootfs was never meant to be a
daily driver):
- `steam-jupiter-oobe`'s launcher **deletes the entire Steam install on every
  launch by design** — patched to persistent stable behavior; the OTA (or
  `pacman -S steam-jupiter-stable`) supersedes it properly. This bug presents
  as an endless client-update + re-login loop and also breaks the client's
  Store/Community views.
- SDDM autologin targets user `steamos`, which doesn't exist (uid 1000 is
  `deck`) — presents as an unrecoverable black screen at session start. Fixed
  with a drop-in (`User=deck`).
- Session set to **Plasma X11**: `kwin_wayland` grabs the wrong GPU on this
  dual-GPU machine (black screen); X11 handles multi-GPU correctly.
- pacman keyring ships uninitialized (documented; init is one command).

**Installer script (`repair_device.sh`) hardening for non-Deck hardware:**
- `DISK`/`DISK_SUFFIX` env-overridable: `sudo DISK=/dev/sda DISK_SUFFIX= ./repair_device.sh all`
- NVMe sanitize skipped on non-NVMe targets
- Text-prompt fallback when zenity has no display (`NOPROMPT=1` also works)
- Auto-unmount of target partitions the desktop automounter grabbed

**Quality of life:**
- `/opt/si-tools/` on installed systems: `enable-gaming-mode.sh` /
  `disable-gaming-mode.sh` (the in-UI session-switch buttons fail silently on
  non-Deck hardware — a polkit issue, under investigation), plus diagnostic
  helpers battle-tested during bring-up

## Key findings (the hard-won knowledge)

1. **`amdgpu.dc=1` is the whole ballgame for Gaming Mode.** On SI hardware the
   modern Display Core is *opt-in* (default = legacy path). Legacy has no
   atomic modesetting; gamescope refuses to run without it. DC initializes
   cleanly on DCE 6.0 (`Display Core v3.2.334 initialized on DCE 6.0`) — the
   community folklore that DC must be disabled on SI (`dc=0`) is, at least on
   this hardware and kernel, **wrong in both directions**: `dc=0` is a no-op
   (already the default), and `dc=1` works and unlocks the full Deck UI.
2. **The atomic-update keep-list only preserves `/etc`.** A kernel cannot be
   keep-listed; hence the self-heal service + `/home` staging design.
3. **The evlaV mirror moved**: `gitlab.com/evlaV` is dead (final commit "the
   beginning of the end"); the live mirror is `github.com/evlaV/jupiter`
   (branch `3.8`) and `github.com/evlaV/linux-integration`.
4. **RADV works on GCN 1.0**: both D300s expose Vulkan 1.3 (`RADV PITCAIRN`) —
   enough for DXVK 2.x/Proton. DX12 (vkd3d) is not viable on GFX6.
5. Steam's desktop client runs its Chromium in software mode on GFX6 (its own
   blocklist) — fine on genuine SteamOS; the visible breakage on the OOBE
   build came from the launcher bug above, not the GPU.

## Repo layout

```
kernel-build/           Dockerfile + PKGBUILD (config-neptune carries the 2-line SI change)
scripts/                build-installer-image.sh — produces the flashable image
artifacts/              install scripts, self-heal units, helper tools, INSTALL.md
                        (the built .img and .pkg.tar.zst binaries are NOT in git — build or ask)
docs/trashcan-chronicle.md   The full three-day story, written as it happened
docs/superpowers/       Original implementation plan with self-annealing notes
```

## Reproducing

1. Build the kernel: see `kernel-build/` (Docker, `linux/amd64`; expect hours
   under emulation). Verify `CONFIG_DRM_AMDGPU_SI=y` in the final `.config`
   **before** compiling — configs silently drop options with unmet deps.
2. Fetch Valve's `steamdeck-oobe-repair-20260707.10-3.8.14.img.bz2` from
   `steamdeck-images.steamos.cloud/recovery/`.
3. `scripts/build-installer-image.sh` (paths at the top; Docker required).
4. Flash the 7.6 GB image, boot with Option-key, then:
   `sudo DISK=/dev/sda DISK_SUFFIX= NOPROMPT=1 ~/tools/repair_device.sh all`
5. Post-install: see `artifacts/INSTALL.md` (short version: take the OTA).

## Status

Everything works: boot, display (Display Core on DCE 6.0), desktop (Plasma
X11), Vulkan on both GPUs, Steam client incl. Store, Big Picture, and **Gaming
Mode** (gamescope embedded session). Known open item: the in-UI session-switch
buttons need a polkit rule (use `/opt/si-tools/` scripts meanwhile).

## Credits

- Valve — SteamOS, and for leaving the sources findable
- the evlaV mirror maintainer(s) — "dedicated to the memory of Aaron Swartz"
- V10lator's linux-charcoal — proof the kernel build path works, and the C23
  libbpf patch pointer
- Built over three days of collaborative archaeology between a human with a
  screwdriver and USB sticks, and Claude doing the reading.
