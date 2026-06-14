## Overview

Ubuntu 24.04 LTS (Noble Numbat) **Server** images for the **Radxa ROCK 5B Plus** (Rockchip RK3588).

This repository is a stripped-down fork of [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip), the community project that ports Ubuntu to Rockchip hardware. Upstream supports ~30 boards across several Ubuntu releases and both server and desktop flavors. We only need **Ubuntu 24.04 LTS Server on the ROCK 5B+**, so everything else — the other boards, the other Ubuntu suites, and the desktop flavor — has been removed to keep the build small, fast, and easy to maintain.

On top of that trimmed base we carry one functional change: a device-tree overlay that fixes **HDMI-in audio capture** on the ROCK 5B+ (see [issue #1057](https://github.com/Joshua-Riek/ubuntu-rockchip/issues/1057)). It is compiled and registered automatically during the image build.

All credit for the underlying port — the kernel, U-Boot, and the GPU/multimedia stack — belongs to the upstream [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) project. If you have a different board, want the desktop image, or want a different Ubuntu release, please use upstream instead.

## What's different from upstream

* Scoped to a single target: **`rock-5b-plus` × `noble` (Ubuntu 24.04 LTS) × `server`**.
* Removed all other boards, the `jammy`/`oracular`/`plucky` suites, the desktop flavor, and the U-Boot trees and firmware helpers only those targets used.
* Added the HDMI-in audio fix as a device-tree overlay applied during the image build.
* CI builds on native arm64 runners (no qemu emulation) with the kernel/U-Boot and live-build downloads cached, so a full image build takes minutes rather than hours.

For background, supported features, and the GPU/multimedia stack, refer to the upstream project and its [wiki](https://github.com/Joshua-Riek/ubuntu-rockchip/wiki).

## Building an image

The build runs as root on an `arm64`-capable Linux host (this is what the CI does). See `CLAUDE.md` for the full build pipeline; the short version:

```bash
sudo ./build.sh --board=rock-5b-plus --suite=noble --flavor=server
```

The final `.img.xz` lands in `images/`. CI artifacts are produced by the `Build` workflow under the repository's Actions tab.

## Installation

Use a good, reliable, and fast SD card. Most boot or stability problems come from an insufficient power supply or the SD card (a bad card, a bad reader, a corrupted write, or a card that is too slow).

Write the `xz`-compressed image (no need to unpack it first) to your SD card with a tool that verifies the result, such as [USBImager](https://bztsrc.gitlab.io/usbimager/) or [balenaEtcher](https://www.balena.io/etcher).

## Boot the system

Insert the SD card into the slot on the board and power on the device. The first boot may take up to two minutes, so please be patient.

## Login information

You can log in through HDMI, a serial console connection, or SSH. The predefined user is `ubuntu` and the password is `ubuntu`; you will be asked to change it on first login.

## HDMI-in audio

The stock device tree binds the ROCK 5B+ HDMI-RX sound card to a DUMMY codec, so the capture device appears but produces no audio. During the image build, `scripts/fix-hdmiin-audio.sh` compiles `scripts/fix-hdmiin-audio.dts` into a device-tree overlay, installs it alongside the kernel's overlays, and enables it via `U_BOOT_FDT_OVERLAYS` in `/etc/default/u-boot`. The overlay rebinds the sound card to the real `hdmirx` controller. Credit for the overlay goes to the contributors on [issue #1057](https://github.com/Joshua-Riek/ubuntu-rockchip/issues/1057).

---
> Ubuntu is a trademark of Canonical Ltd. Rockchip is a trademark of Fuzhou Rockchip Electronics Co., Ltd. The Ubuntu Rockchip project is not affiliated with Canonical Ltd or Fuzhou Rockchip Electronics Co., Ltd. All other product names, logos, and brands are property of their respective owners. The Ubuntu name is owned by [Canonical Limited](https://ubuntu.com/).
