# Rebuilding the SI-enabled linux-neptune-616 kernel

This directory holds everything needed to rebuild Valve's `linux-neptune-616`
(SteamOS 3.8, 6.16.12-valve27) with Southern Islands (GCN 1.0) and Sea Islands
(GCN 2.0) support turned back on.

## The diff

`linux-neptune-616/config-neptune` is Valve's config fragment with two lines
flipped:

```
CONFIG_DRM_AMDGPU_CIK=y     # was: # CONFIG_DRM_AMDGPU_CIK is not set
CONFIG_DRM_AMDGPU_SI=y      # was: # CONFIG_DRM_AMDGPU_SI is not set
```

`CONFIG_DRM_RADEON` stays unset. With radeon absent, amdgpu's `si_support` and
`cik_support` default to 1, so no boot flag is needed. The base Arch `config`
already carries `CONFIG_DRM_AMD_DC_SI=y`, which now takes effect. The final
`.config` differs from Valve's by exactly those three lines. The `PKGBUILD` is
Valve's with the sha256 for the edited `config-neptune` updated.

`c23-libbpf.patch` is upstream commit d70f79fef658 ("libbpf: Fix
-Wdiscarded-qualifiers under C23"). It is needed because current Arch ships
GCC 15, which defaults to C23, and the tree builds its host tools with
`-Werror`. It only touches a build-time tool. The kernel image and amdgpu are
unaffected.

## Build (Docker, any host)

Tested on Apple Silicon under Rosetta. Expect roughly 2.5 hours at `-j10` on an
M1 Max. Native x86_64 will be faster.

```bash
cd kernel-build
docker build --platform linux/amd64 -t neptune-kernel-build .

# Keep the source tree and objects in a named volume, NOT on a bind mount
# from macOS (the file-sharing layer kills I/O performance).
docker volume create neptune-work
docker run -it --platform linux/amd64 --name neptune-build \
  -v neptune-work:/work -v "$PWD":/pkg:ro \
  neptune-kernel-build bash
```

Inside the container:

```bash
cp -r /pkg/linux-neptune-616 /work/ && cd /work/linux-neptune-616

# 1. Fetch + configure only. Clones about 4 GB of kernel git.
makepkg --nobuild --noconfirm

# 2. HARD GATE: confirm SI made it into the merged .config before spending hours.
grep -E 'DRM_AMDGPU_SI|DRM_AMDGPU_CIK|DRM_AMD_DC_SI|DRM_RADEON' src/*/.config
#    expect: CONFIG_DRM_AMDGPU_SI=y  CONFIG_DRM_AMDGPU_CIK=y  CONFIG_DRM_AMD_DC_SI=y
#            # CONFIG_DRM_RADEON is not set

# 3. Apply the C23 patch BEFORE the first build, and tell git to ignore the
#    change so the kernel does not stamp itself "-dirty" (which breaks the
#    package() step with a path mismatch).
cd src/linux-integration* 2>/dev/null || cd src/*/
patch -Np1 < /pkg/c23-libbpf.patch
git update-index --assume-unchanged tools/lib/bpf/libbpf.c
cd /work/linux-neptune-616

# 4. Build. -j to taste; OOM shows up as exit 137 / "cc1 killed", retry lower.
MAKEFLAGS=-j10 makepkg --noextract --noconfirm
```

Output: `linux-neptune-616-6.16.12.valve27-2.1-x86_64.pkg.tar.zst` and the
`-headers` package. Copy them to `artifacts/`.

## Verify the package, not just the config

Every layer caught something during the original build, so check the artifact
you are about to ship:

```bash
# The packaged kernel carries its config embedded (IKCONFIG). Prove SI is in it.
tar -xOf linux-neptune-616-6.16.12.valve27-2.1-x86_64.pkg.tar.zst \
    usr/lib/modules/*/vmlinuz > /tmp/vmlinuz
# extract-ikconfig is in the headers package or any kernel tree's scripts/
scripts/extract-ikconfig /tmp/vmlinuz | grep -E 'DRM_AMDGPU_(SI|CIK)=|DRM_AMD_DC_SI='

# amdgpu.ko should reference pitcairn firmware (SteamOS ships the blobs).
tar -xOf linux-neptune-616-*-x86_64.pkg.tar.zst usr/lib/modules/*/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst \
    | zstd -d | strings | grep -c pitcairn
```

The version string must match Valve's stock package exactly (no `-dirty`), so
pacman treats it as a reinstall and the self-heal service can compare cleanly.

## Gotchas collected the hard way

- pacman's seccomp download sandbox fails under Rosetta. The Dockerfile sets
  `DisableSandbox`.
- `docker run -i` (not `-t`) when piping heredocs into the container.
- Patching the tree after `makepkg --nobuild` without `assume-unchanged` makes
  `CONFIG_LOCALVERSION_AUTO` append `-dirty`. If that happens: set
  assume-unchanged, `rm -rf pkg/`, rerun `makepkg --noextract`. It reuses all
  objects and only relinks (30 to 60 minutes).
- BTF generation (pahole) is the slowest single-threaded step. The long quiet
  tail at the end is normal.
- The Docker Desktop VM needs about 8 GB RAM for `-j8`.

## When Valve bumps the kernel

When SteamOS moves to `linux-neptune-618` or later, pull the new
`linux-neptune-6xx/` directory from `github.com/evlaV/jupiter` (branch `3.8` or
whatever is current), reapply the two-line change to its `config-neptune`,
update the sha256 in the PKGBUILD, and repeat the steps above. Check whether
the C23 patch still applies; newer upstream trees already carry it.

## License

These files derive from Valve's SteamOS packaging (via the evlaV mirror), Arch
Linux's linux package, and the Linux kernel. GPL-2.0-only.
