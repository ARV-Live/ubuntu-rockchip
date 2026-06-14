# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo builds bootable Ubuntu disk images for the **Radxa ROCK 5B Plus** (Rockchip RK3588) single-board computer. It is a trimmed fork of `Joshua-Riek/ubuntu-rockchip`: upstream supports ~30 boards and several Ubuntu suites, but this fork is scoped to **one board (`rock-5b-plus`) × one suite (`noble` = Ubuntu 24.04 LTS) × one flavor (`server`)**. The output is a single `.img.xz`. (The `desktop` flavor was dropped — its `lb build` is slow/flaky and unused here.)

It is **not** an application codebase — there is no compiled app, no unit tests, and almost everything is Bash plus declarative shell-config files and Debian packaging.

## Build commands

The build **must run as root on an `arm64`-capable Linux host** (CI uses `ubuntu-latest` with `qemu-user-static` for the chroot). It will not run on this macOS dev machine — edits here are pushed and built in GitHub Actions. Treat local "builds" as not runnable; verify by reading scripts and CI logs instead.

```bash
# Full image: kernel (if missing) -> u-boot (if missing) -> rootfs -> disk image
sudo ./build.sh --board=rock-5b-plus --suite=noble --flavor=server

# Partial builds (each maps to a script in scripts/)
sudo ./build.sh --suite=noble --kernel-only               # -> build/linux-*.deb
sudo ./build.sh --board=rock-5b-plus --uboot-only         # -> build/u-boot-rock-5b-plus_*.deb
sudo ./build.sh --suite=noble --flavor=server --rootfs-only  # -> build/ubuntu-*.rootfs.tar.xz

# Discover valid argument values
./build.sh --board=help     # lists config/boards/*  (only rock-5b-plus)
./build.sh --suite=help     # lists config/suites/*  (only noble)
./build.sh --flavor=help    # lists config/flavors/* (server)

./build.sh --clean ...      # wipe build/ first (also unmounts stale chroot mounts)
./build.sh --launchpad ...  # pull prebuilt kernel/u-boot from the jjriek PPA instead of compiling
./build.sh --verbose ...    # set -x
```

Artifacts: intermediate `.deb`/`.tar.xz` land in `build/` (gitignored), final images in `images/` (gitignored). Build logs are tee'd to `build/logs/build-<timestamp>.log`.

## Architecture: the build pipeline

`build.sh` is an argument parser + orchestrator. It sources the matching config files (which only `export` env vars and define shell-function hooks), then calls the `scripts/` in order. There is no state beyond env vars and files in `build/`.

```
config/suites/noble.sh     ─┐  (RELASE_VERSION, KERNEL_REPO/BRANCH, EXTRA_PPAS)
config/flavors/<flavor>.sh ─┼─ sourced into env by build.sh / each script
config/boards/rock-5b-plus.sh ┘ (UBOOT_PACKAGE, UBOOT_RULES_TARGET, config_image_hook__rock-5b-plus())
            │
            ▼
build-kernel.sh   clones Joshua-Riek/linux-rockchip @ KERNEL_BRANCH (noble = 6.1), builds linux-*.deb via debian/rules
build-u-boot.sh   clones upstream u-boot (packages/u-boot-radxa-rk3588/debian/upstream), grafts our debian/, builds u-boot-rock-5b-plus_*.deb
build-rootfs.sh   builds a noble/FLAVOR rootfs with Ubuntu live-build (Joshua-Riek/livecd-rootfs fork) -> ubuntu-24.04-preinstalled-<flavor>-arm64.rootfs.tar.xz  (board-agnostic)
config-image.sh   extracts rootfs into build/rootfs, chroots in, installs the kernel+u-boot .debs, runs config_image_hook__rock-5b-plus, repacks -> *.rootfs.tar
build-image.sh    partitions a loopback disk image, lays down the rootfs, dd's u-boot to the raw disk, compresses -> images/*.img.xz (+ .sha256)
```

Key separation (inherited from upstream): **the rootfs is board-independent**; everything board-specific happens in `config-image.sh` (software/firmware via the chroot hook) and `build-image.sh` (partition layout + bootloader placement). The CI still reflects this — it builds each rootfs once (per flavor) and feeds it into the image build — even though only one board remains.

### The config layer (the main extension surface)

Board behavior lives entirely in `config/boards/rock-5b-plus.sh`. It exports metadata (`BOARD_NAME`, `BOARD_SOC`, ...), the U-Boot build target (`UBOOT_PACKAGE=u-boot-radxa-rk3588` + `UBOOT_RULES_TARGET=rock-5b-plus-rk3588`), `COMPATIBLE_SUITES`/`COMPATIBLE_FLAVORS` arrays, and defines a function:

- `config_image_hook__rock-5b-plus(rootfs, overlay, suite)` — runs **inside `config-image.sh`** after the kernel/u-boot are installed, with the chroot mounted. It `chroot ... apt-get install`s the board's multimedia firmware (panfork Mesa, libmali, camera-engine), copies files from `overlay/`, and `systemctl enable`s board services (e.g. `alsa-audio-config`). This is the place to add board-specific runtime setup.
- `build_image_hook__rock-5b-plus(writable)` — runs in `build-image.sh` after the rootfs is laid onto the image and right *before* `u-boot-update`, with `$1` = the mounted writable root. Used here to apply the HDMI-in audio fix: `scripts/fix-hdmiin-audio.sh` compiles `scripts/fix-hdmiin-audio.dts` to a `.dtbo`, drops it in the kernel's `device-tree/rockchip/overlay/` dir, and registers it in `/etc/default/u-boot` (`U_BOOT_FDT_OVERLAYS`) so `u-boot-update` writes it into the extlinux config (issue #1057). This hook is the right place for anything that must touch the final on-disk image (dtbs, bootloader config) rather than the chroot.

`UBOOT_PACKAGE` points at `packages/u-boot-radxa-rk3588`, a Debian `debian/` overlay (`rules`, `targets.mk`, `upstream` pinning a git COMMIT/BRANCH, `patches/`, `rkbin/` blobs) grafted onto upstream U-Boot source. `UBOOT_RULES_TARGET` selects which board target inside that tree to build. (Upstream had four such trees for different SoC families; this fork keeps only the radxa-rk3588 one the ROCK 5B+ uses.)

### overlay/

Static files copied into images by the hooks: cloud-init seed (`boot/firmware/{meta-data,user-data,network-config}` — used for server images by `build-image.sh`), plus the `alsa-audio-config` script and its systemd unit for audio bringup. Files here are **not** installed automatically — the board's `config_image_hook__` must explicitly `cp` them in and enable the service. (Upstream shipped many more Wi-Fi/BT helpers here; only the ones the ROCK 5B+ uses remain.)

## CI (`.github/workflows/`)

- `build.yml` — manual (`workflow_dispatch`); the reference pipeline. Builds rootfs (noble × {desktop,server}) and kernel (noble) once, then fans out the `build` job over `board=[rock-5b-plus]`. Matrix is hardcoded. **This is the workflow to dispatch when verifying a change** (`gh workflow run build.yml`).
- `nightly.yml` (cron, currently `disabled_fork`) and `release.yml` (manual) — generate their board/suite/flavor matrix dynamically by sourcing every `config/*` file, so they self-trim to whatever configs exist (now just rock-5b-plus/noble). Both use `--launchpad` (prebuilt kernel/u-boot from the jjriek PPA) for speed.
- `stale.yml` — issue housekeeping.

Note: every job runs `git lfs fetch && git lfs checkout`. This fork does **not** actually use Git LFS (no `.gitattributes`; the U-Boot `rkbin/*.elf|*.bin` blobs are committed directly), so those steps are harmless no-ops. The CI dependency list (`apt-get install ...` in each workflow) is the authoritative set of host build dependencies.

## Conventions / gotchas

- The env var is misspelled **`RELASE_VERSION`** / `RELASE_NAME` (no second `E`) throughout — match the existing spelling, do not "fix" it or you'll break every script that reads it.
- `build.yml` hardcodes the suite→version mapping (`24.04`, kernel `6.1`) in artifact names; `nightly.yml`/`release.yml` derive it at runtime from `RELASE_VERSION` in `config/suites/noble.sh`. If you ever re-add a suite, update both.
- Scripts assume a clean re-entrant `build/`: each guards work with `find ... | tail -n1` existence checks and skips recompiling if the `.deb`/`.tar.xz` already exists. To force a rebuild of one stage, delete its artifact from `build/` (or use `--clean`).
- Kernel and U-Boot are pinned to forks/commits maintained by the upstream project owner (`Joshua-Riek/linux-rockchip`, `Joshua-Riek/livecd-rootfs`, and the `jjriek` Launchpad PPAs); the multimedia/GPU stack (panfork Mesa, libmali, camera-engine) comes from those PPAs, pinned at priority 1001 for noble in `build-rootfs.sh`.
