# The Trash Can Chronicle
### SteamOS 3.8 + working Vulkan on a 2013 Mac Pro's "impossible" GPUs

> Written as it happened. Day 1 and Day 2 are left as they were, including
> conclusions that Day 3 overturned (`amdgpu.dc=0`, Plasma Wayland). Day 3 is
> where the record gets corrected. If you only want the current truth, read the
> README.

**Hardware:** Apple Mac Pro (Late 2013, the trash can) · dual AMD FirePro D300
(Pitcairn/Curacao XT, GCN 1.0 "Southern Islands", 2 GB, 1280 shaders each) ·
AHCI blade SSD. **Software:** SteamOS 3.8, kernel linux-neptune-616 (6.16.12).

## The problem (Day 0)
SteamOS installed but displayless: `amdgpu: amdgpu is built without SI support.`
Valve compiles Southern Islands support out of the Deck kernel (the Deck is
RDNA2). No driver binds → no display, no Vulkan, no OpenGL. The runtime flag
`amdgpu.si_support=1` is useless: the code isn't in the binary.

## Day 1 (2026-08-11): the kernel
- Found the sources: the famous GitLab mirror (evlaV/jupiter-PKGBUILD) is dead.
  Final commit literally titled "the beginning of the end". The living mirror is
  **github.com/evlaV/jupiter**, branch `3.8`, `linux-neptune-616` @ 6.16.12-valve27.
- The fix is comically small: Valve's config is Arch's stock config (which already
  enables SI) minus a fragment that disables it. Flip two lines in
  `config-neptune`. Verified diff of the final .config vs stock: exactly three
  lines (SI, CIK, and dependency-driven DC_SI).
- Built in Docker (linux/amd64 under Rosetta on an M1 Max, ~2.5 h at -j10).
  Potholes: pacman's seccomp sandbox breaks under Rosetta; GCC 15/C23 broke
  libbpf (fixed by upstream commit d70f79fef658); patching the tree post-prepare
  made the kernel stamp itself `-dirty` (cured with git assume-unchanged + relink).
- Verified at every layer: .config, packaged vmlinuz's embedded IKCONFIG,
  amdgpu.ko's firmware references (pitcairn_*.bin, and SteamOS ships them).
- Learned the atomic-update keep-list only protects /etc, so a kernel cannot
  survive OS updates that way. Countermeasure: a keep-listed systemd oneshot
  that reinstalls the kernel from /home (which persists) and reboots once.
- Built a custom installer: Valve's official 3.8.14 oobe-repair image with the
  SI kernel chroot-installed into its rootfs. Key discovery: the recovery image
  IS the payload: repair_device.sh dd's its own rootfs onto the target, so one
  kernel swap fixes both the live installer and every system it installs.

## Day 2 (2026-08-13): the machine
- First boot of the custom USB: black screen. Diagnosis ladder:
  - GRUB menu unreachable (timeout=0, Valve's steamenv resets it) → edited the
    stick's grub.cfg from macOS (the EFI partition is FAT).
  - Verbose + `amdgpu.dc=0` → **display lives.** The modern DC display core
    black-screens on DCE6-era hardware; the legacy display path works.
  - SDDM then blanked the screen unrecoverably → `systemd.unit=multi-user.target`
    → reliable console boot.
- Reimaging the internal disk fought back three times: zenity prompts with no
  display (NOPROMPT=1), an NVMe-only sanitize step on an AHCI disk (skipped),
  and auto-mounted target partitions (unmounted). All three now fixed in the
  image build script.
- Pre-first-boot chroot into both A/B slots: `amdgpu.dc=0` + GRUB_TIMEOUT=5 in
  /etc/default/grub, default target = console.
- **First native boot: login prompt on the trash can's own display.**
- dmesg: both D300s fully initialized (dce_v6_0, VBIOS via VFCT, dpm, 20 CUs).
- vulkaninfo: **two discrete GPUs, "AMD Radeon R9 200 Series (RADV PITCAIRN)",
  Vulkan 1.3.330**, enough for DXVK 2.x/Proton.

## Scoreboard
| Goal | Result |
|---|---|
| SI-enabled kernel, minimal diff | ✅ 3 config lines, stock version string |
| Survives SteamOS updates | ✅ self-heal service (keep-list can't do it) |
| Custom installer image | ✅ built, battle-tested, v2 fixes scripted |
| Display on D300s | ✅ (Day 2: via legacy path; Day 3: via amdgpu.dc=1, Display Core on DCE 6.0) |
| Vulkan | ✅ 1.3 on both GPUs via RADV |
| Desktop session | ✅ (Day 2: Plasma Wayland; Day 3: Plasma X11, see below) |
| Gaming Mode | ✅ (Day 3) gamescope embedded session, full Deck UI |

## Epilogue: the SDDM "GPU bug" that wasn't
The unrecoverable black screen at desktop start, the one that looked like a
GFX6 compositor failure, was SDDM autologging into user **`steamos`, which
doesn't exist on the image** (uid 1000 is `deck`). Autologin failed, the
greeter died with it, screen went dark. One three-line config drop-in
(`User=deck`, `Session=plasma.desktop`) later: full Plasma Wayland desktop,
Steam bootstrapping over it. The scariest-looking bug of the project was a
typo-grade misconfiguration in Valve's image. Installer image v2 (all fixes
baked, every one verified in the built artifact) is ready to flash.

**State at the end of Day 2:** power button → GRUB (5 s menu) → SI kernel → both D300s up →
SDDM → Plasma Wayland → Steam. A 2013 trash can, reborn as a Steam machine.

## Day 3 (2026-08-14): Gaming Mode, and three things Day 2 got wrong
Overnight the machine took Valve's silent OTA and landed on genuine SteamOS
3.8.16 on the other A/B slot. The self-heal service did its job and the SI
kernel came back. That gave a clean baseline to re-test everything on, and
three Day 2 conclusions did not survive:

1. **`amdgpu.dc=0` was never load-bearing.** On Southern Islands the Display
   Core is opt-in; legacy was the default all along, so `dc=0` changed nothing.
   Worse, the folklore had it backwards: `dc=1` initializes cleanly
   (`Display Core v3.2.334 initialized on DCE 6.0`) and is *required*, because
   gamescope needs atomic modesetting and the legacy path has none. One
   grub.cfg edit later, **Gaming Mode came up.** Full Deck UI on a 2013 Mac Pro.
2. **The one hard hang during the DC experiments was probably not DC.** That
   boot had also dropped Valve's `amd_iommu=off`. Lesson: change one flag at a
   time, and leave Valve's stock flags alone.
3. **Plasma Wayland was luck.** On the genuine OS `kwin_wayland` picked the
   headless D300 and the screen went black. The monitor hangs off the second
   card (the HDMI port is an internal DP converter, so it enumerates as DP).
   Plasma X11 handles the dual-GPU layout correctly. Session set to
   `plasmax11.desktop`.

Then the Steam client, which had looked GPU-broken on the OOBE build (Store and
Community tabs blank, popups as 2x1 surfaces), turned out to be two Valve
recovery-image quirks stacked on top of each other:

- `steam-jupiter-oobe`'s launcher `rm -rf`s the entire Steam install on every
  launch, by design (it is a repair stick). On a dd-installed daily driver that
  is an endless update-and-relogin loop. `pacman -S steam-jupiter-stable`
  (after `pacman-key --init && pacman-key --populate`, the keyring ships
  empty) fixes it for good. The image also patches the launcher so the interim
  behaviour is sane.
- Steam's Chromium runs in software mode on GFX6 by its own blocklist. Slower,
  but everything renders once the launcher is fixed.

Last, the in-UI "Switch to Desktop" and "Return to Gaming Mode" buttons fail
silently here. `steamos-session-select` does a privileged write that polkit
only allows on Deck hardware. Two tiny scripts in `/opt/si-tools/` do the same
thing by hand. A proper polkit rule is the one thing still open.

Image v3 was rebuilt with all of this baked in (`dc=1` on every boot entry and
in `/etc/default/grub`, X11 session, patched launcher, expanded keep-list so an
immediate OTA carries every fix onto genuine SteamOS), verified file by file in
the built image, and flashed once.

**Final state:** power button → SI kernel → both D300s up with Display Core →
SDDM → gamescope → the Steam Deck UI. On Valve's own current OS, surviving
Valve's own updates. A 2013 trash can, reborn as a Steam machine.

## Morals
1. The distance between "impossible" and "working" was two config lines, plus
   two days of everything around them.
2. Verify at the layer you shipped, not the layer you edited (the .config, the
   package, the vmlinuz, the booted kernel: each caught something).
3. Read the actual implementation (keep-list, repair_device.sh, steamos-chroot)
   instead of trusting folklore.
4. When a machine has no display, make every failure verbose and every boot
   interruptible. The fixes were easy once the symptoms were visible.
