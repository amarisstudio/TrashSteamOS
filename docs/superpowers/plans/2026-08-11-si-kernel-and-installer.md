# SteamOS 3.8 SI-Enabled Kernel + Custom Installer Plan

> **For agentic workers:** Executed inline in-session (long-running Docker builds
> need live supervision). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `linux-neptune-616` (6.16.12-valve27) with `CONFIG_DRM_AMDGPU_SI=y`
and `CONFIG_DRM_AMDGPU_CIK=y` so amdgpu binds the dual FirePro D300 (Southern
Islands / GCN 1.0) GPUs in a 2013 Mac Pro, then bake that kernel into a flashable
SteamOS installer image.

**Architecture:** Build Arch packages with `makepkg` inside a `--platform linux/amd64`
Arch container on Docker Desktop (Rosetta-accelerated, benchmarked ~native speed).
Kernel config change is a two-line edit to the `config-neptune` fragment; the base
Arch `config` already carries SI/CIK/DC_SI `=y`, so flipping the fragment's
"is not set" lines is the entire diff.

**Tech stack:** Docker Desktop (Rosetta), archlinux:base-devel image, makepkg,
evlaV GitHub mirrors.

## Global Constraints

- Source of truth: `github.com/evlaV/jupiter`, branch `3.8`, dir `linux-neptune-616`
  (`_tag=6.16.12-valve27`, `pkgrel=2.1`). The GitLab `evlaV/jupiter-PKGBUILD` mirror
  is stale (stops at 6.15.8-valve1, final commit 2026-08-06 "the beginning of the end").
  Kernel source: `github.com/evlaV/linux-integration` tag `6.16.12-valve27` (verified present).
- Minimal diff: only `CONFIG_DRM_AMDGPU_SI=y` + `CONFIG_DRM_AMDGPU_CIK=y` in
  `config-neptune` (plus the PKGBUILD sha256 for that file). `pkgver`/`pkgrel`
  unchanged so the package is byte-for-byte comparable to stock except the SI change.
- `CONFIG_DRM_AMD_DC_SI=y` returns automatically from the Arch base config once SI
  is enabled (its only blocker was the SI dependency). Report it in the verify diff;
  do not suppress it — it is required for proper display-core support on SI.
- `CONFIG_DRM_RADEON` stays unset — with radeon absent, `amdgpu.si_support` defaults
  to 1, so no kernel cmdline flags are needed.
- Verify `.config` AFTER `make olddefconfig` and BEFORE compiling; abort if the
  options were dropped (unmet deps) and report the dependency chain instead.
- Final artefacts go to `artifacts/` in the project root (obvious USB-copy location).
- Build parallelism `-j8` (Docker VM has 10 CPUs but only ~7.7 GiB RAM; pahole/BTF
  is the memory peak).

---

### Task 1: Build container

**Files:** Create `kernel-build/Dockerfile`

- [ ] FROM `--platform=linux/amd64 archlinux:base-devel`; `pacman -Syu` +
  makedepends (`bc cpio gettext libelf pahole perl python tar xz git openssh`);
  non-root `builder` user with passwordless sudo (makepkg refuses root).
- [ ] `docker build --platform linux/amd64 -t neptune-kernel-build kernel-build/`

### Task 2: PKGBUILD + config change

**Files:** Create `kernel-build/linux-neptune-616/` (PKGBUILD, config, config-neptune)

- [ ] Sparse-clone `evlaV/jupiter` branch `3.8`, copy `linux-neptune-616/`.
- [ ] In `config-neptune` replace:
      `# CONFIG_DRM_AMDGPU_CIK is not set` → `CONFIG_DRM_AMDGPU_CIK=y`
      `# CONFIG_DRM_AMDGPU_SI is not set` → `CONFIG_DRM_AMDGPU_SI=y`
      (leave `# CONFIG_DRM_RADEON is not set` alone), with a one-line comment.
- [ ] Update `sha256sums` entry for `config-neptune` in PKGBUILD (`sha256sum` of edited file).
- [ ] Show the user the full diff vs stock.

### Task 3: Prepare + verify config (gate before the expensive build)

- [ ] Container run: `makepkg --nobuild --noconfirm` (clones ~3–4 GB kernel git,
  merges config fragments, runs `make olddefconfig`). Keep the src tree in a named
  docker volume (`neptune-src`) so the build step reuses it; do NOT build on the
  osxfs bind mount (kills I/O perf).
- [ ] `grep -E 'DRM_AMDGPU_SI|DRM_AMDGPU_CIK|DRM_AMD_DC_SI|DRM_RADEON|DRM_AMDGPU=' src/*/.config`
  Expected: `CONFIG_DRM_AMDGPU_SI=y`, `CONFIG_DRM_AMDGPU_CIK=y`, `CONFIG_DRM_AMD_DC_SI=y`,
  `CONFIG_DRM_AMDGPU=m`, radeon unset.
- [ ] Show the user the `diff -u config .config` output that prepare() prints.
- [ ] HARD GATE: if SI is not `=y` in `.config`, stop, run
  `make olddefconfig` dependency analysis (`scripts/config` + menuconfig search) and
  report unmet deps to the user. Do not enable anything else silently.

### Task 4: Compile + package

- [ ] `makepkg --noextract --noconfirm` with `MAKEFLAGS=-j8` (expected 1.5–3 h under
  Rosetta; run detached with `run_in_background`, poll logs).
- [ ] Copy `linux-neptune-616-6.16.12.valve27-2.1-x86_64.pkg.tar.zst` +
  `-headers` package to `artifacts/`.
- [ ] Sanity: list package contents; confirm `usr/lib/modules/*/vmlinuz` +
  `amdgpu.ko.zst` present; `zgrep` the packaged config if included.

### Task 5: Install instructions

- [ ] Write `artifacts/INSTALL.md`: steamos-readonly disable → pacman -U both
  packages → mkinitcpio/boot update as the package hooks do → keeplist file in
  `/etc/atomic-update.conf.d/` → steamos-readonly enable → reboot + verification
  (`zcat /proc/config.gz | grep DRM_AMDGPU_SI`, `dmesg | grep -i amdgpu`).

### Task 6 (Phase 2): Installer image recon

- [ ] Locate official SteamOS 3.8 recovery/installer image (steamdeck.steampowered.com
  recovery instructions → `steamdeck-recovery-*.img.bz2`).
- [ ] Inspect partition table + contents inside a privileged amd64 container
  (losetup works in Docker Desktop's Linux VM).
- [ ] Map: ESP/EFI partitions, recovery rootfs, and the *payload* rootfs image the
  installer writes to the target disk. Determine whether the payload carries its own
  kernel (it does — the installed system's kernel comes from the payload, not the
  recovery boot kernel).
- [ ] Feasibility verdict: need to swap kernel in BOTH the recovery boot chain
  (so the installer itself displays on the D300s) and the payload rootfs (so the
  installed system boots with SI support). Report honestly if the payload format
  (e.g. casync store / rauc bundle / verity-sealed rootfs) makes this impractical.

### Task 7 (Phase 2): Build the .img

- [ ] If feasible: modify inside privileged container, repack, emit
  `artifacts/steamos-3.8-si-installer.img` + SHA256, with dd/balenaEtcher notes.
- [ ] If verity/signing blocks it: document exactly what blocks it and provide the
  best working alternative (e.g. stock installer + immediate post-install kernel
  swap over SSH/console, scripted).

## Self-review notes

- Spec coverage: kernel build (T1–4), verification gate (T3), install commands (T5),
  installer image (T6–7), honesty requirement (T6 verdict step). ✔
- Risk: user's installed SteamOS 3.8 may be a different valve-tag than valve27
  (branch 3.8 HEAD). Package replaces whatever linux-neptune-616 is installed;
  pacman handles same-name upgrade/reinstall. Noted in INSTALL.md.
- Risk: 7.7 GiB VM RAM → use -j8 and retry with -j4 if OOM (exit 137 / cc1 killed).
- Risk: headers package builds fine under Rosetta; no known blockers. BTF (pahole)
  is the slowest single-threaded step — do not panic at the long tail.

## Phase 2 recon results (task 6 complete)

- Image: `steamdeck-oobe-repair-20260707.10-3.8.14.img` (7.56 GiB raw). GPT:
  p1 64M ESP (steamcl), p2 128M efi (GRUB), p3 5G rootfs ext4 (plain, NO verity),
  p4 256M var, p5 2G home ext4 **with casefold** (LinuxKit kernel can't mount —
  use debugfs/e2fsprogs-extra userspace tools).
- Boot chain: steamcl (p1) → grubx64.efi + grub.cfg (p2) → kernel loaded FROM
  ROOTFS `/boot/vmlinuz-linux-neptune-616` by fs-UUID search. So `pacman -U` in a
  chroot of p3 updates both the live installer kernel and the payload. No
  bootloader changes needed.
- Payload mechanism: `~/tools/repair_device.sh` (home partition) dd's the
  recovery's OWN rootfs onto target rootfs-A and rootfs-B, then steamcl-install.
  The recovery rootfs IS the installed OS → SI kernel baked into p3 propagates
  to fresh installs. Image ships kernel 6.16.12-valve24.4; our valve27 replaces it.
- Target-disk gotcha: repair_device.sh hardcodes `DISK=/dev/nvme0n1`,
  `DISK_SUFFIX=p` (lines 17-18). 2013 Mac Pro SSD is AHCI → /dev/sda, suffix "".
  Patch to env-overridable defaults via debugfs write on p5;
  usage: `sudo DISK=/dev/sda DISK_SUFFIX= ./tools/repair_device.sh all`.
- Feasibility verdict: FEASIBLE, no signing/verity blockers on the recovery image.

## Learned during execution (self-annealing)

- First build attempt failed: `tools/bpf/resolve_btfids` → libbpf.c
  -Wdiscarded-qualifiers errors. Cause: glibc ≥2.42/GCC 15 default to C23, where
  strstr/strchr return `const char *`; tree builds host tools with -Werror.
  Fix: upstream commit `d70f79fef658` ("libbpf: Fix -Wdiscarded-qualifiers under
  C23"), saved as `kernel-build/c23-libbpf.patch`, applied with `patch -Np1` in
  the src tree before re-running `makepkg --noextract`. Host-tool-only change;
  kernel image and amdgpu unaffected. (linux-charcoal carries the same patch.)
- pacman in the build image needs `DisableSandbox` in /etc/pacman.conf (seccomp
  fails under Rosetta).
- Patching the git tree post-prepare makes CONFIG_LOCALVERSION_AUTO append
  `-dirty` to kernelrelease → package() path mismatch ("rm .../build: No such
  file"). Fix: `git update-index --assume-unchanged tools/lib/bpf/libbpf.c`
  (patch stays applied, dirty flag clears), rm -rf pkg staging, re-run makepkg
  --noextract — reuses all objects, relinks vmlinux/BTF, re-stamps modules
  (~30-60 min). Apply future patches BEFORE first build and set assume-unchanged
  immediately.
