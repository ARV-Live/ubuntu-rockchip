#!/bin/bash
#
# Apply the ROCK 5B+ HDMI-in audio device-tree overlay fix (issue #1057).
#
# Decoupled from the rest of the build: invoked from build_image_hook__rock-5b-plus
# in build-image.sh, after the rootfs is laid onto the image and right before
# u-boot-update runs. Given the mounted writable root, it:
#   1. compiles fix-hdmiin-audio.dts -> hdmiin-fix.dtbo (dtc, overlay mode)
#   2. drops it into the kernel's device-tree/rockchip/overlay/ directory
#   3. registers it in /etc/default/u-boot (U_BOOT_FDT_OVERLAYS) so the
#      subsequent `u-boot-update` writes it into the extlinux config
#
# See: https://github.com/Joshua-Riek/ubuntu-rockchip/issues/1057

set -eE
trap 'echo "Error: in $0 on line $LINENO"' ERR

writable="$1"
if [ -z "${writable}" ] || [ ! -d "${writable}" ]; then
    echo "Error: writable root '${writable}' does not exist"
    exit 1
fi

if ! command -v dtc > /dev/null; then
    echo "Error: dtc (device-tree-compiler) is required but not installed"
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
dts="${script_dir}/fix-hdmiin-audio.dts"
if [ ! -f "${dts}" ]; then
    echo "Error: overlay source ${dts} not found"
    exit 1
fi

boot="${writable}/boot/firmware"
overlay_ref="device-tree/rockchip/overlay/hdmiin-fix.dtbo"
overlay_dir="${boot}/device-tree/rockchip/overlay"

# The kernel ships its overlays under <boot>/device-tree/rockchip/overlay
# (device-tree is a symlink to the current kernel's dtb dir). If that layout
# is not present, fall back to discovering an existing overlay directory and
# reference the .dtbo by its path relative to the boot directory.
if [ ! -e "${boot}/device-tree" ]; then
    found="$(find "${boot}" -type d -path '*rockchip/overlay' 2>/dev/null | head -n1)"
    if [ -z "${found}" ]; then
        echo "Error: could not locate a device-tree overlay directory under ${boot}"
        exit 1
    fi
    overlay_dir="${found}"
    overlay_ref="${found#"${boot}"/}/hdmiin-fix.dtbo"
fi

echo "Installing HDMI-in audio overlay -> ${overlay_dir}/hdmiin-fix.dtbo"
mkdir -p "${overlay_dir}"

# -@ keeps the __symbols__/__fixups__ needed to resolve the &phandle
# references (hdmirx_ctrler, i2s7_8ch) against the base device tree at load.
dtc -@ -I dts -O dtb -o "${overlay_dir}/hdmiin-fix.dtbo" "${dts}"

# Register the overlay in /etc/default/u-boot so u-boot-update emits an
# `fdtoverlays` entry into the extlinux config on the next run.
defaults="${writable}/etc/default/u-boot"
if [ ! -f "${defaults}" ]; then
    echo "Error: ${defaults} not found (cannot register the overlay)"
    exit 1
fi

# Preserve any overlays already configured, append ours once (idempotent).
current="$(sed -n -E 's/^[[:space:]]*U_BOOT_FDT_OVERLAYS="?([^"]*)"?.*/\1/p' "${defaults}" | head -n1)"
case " ${current} " in
    *" ${overlay_ref} "*) merged="${current}" ;;
    *)                    merged="${current:+${current} }${overlay_ref}" ;;
esac

# Drop any existing (commented or active) line, then write the merged value.
sed -i -E '/^[[:space:]]*#?[[:space:]]*U_BOOT_FDT_OVERLAYS=/d' "${defaults}"
echo "U_BOOT_FDT_OVERLAYS=\"${merged}\"" >> "${defaults}"

echo "Registered overlay in ${defaults}: U_BOOT_FDT_OVERLAYS=\"${merged}\""
