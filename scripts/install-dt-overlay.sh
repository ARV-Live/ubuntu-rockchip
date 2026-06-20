#!/bin/bash
#
# Compile a device-tree overlay and register it so u-boot-update applies it.
#
#   install-dt-overlay.sh <writable-root> <overlay.dts>
#
# Decoupled from the rest of the build: invoked from build_image_hook__rock-5b-plus
# in build-image.sh, after the rootfs is laid onto the image and right before
# u-boot-update runs. Given the mounted writable root and a .dts, it:
#   1. compiles <overlay>.dts -> <overlay>.dtbo (dtc, overlay mode)
#   2. drops it into the kernel's device-tree/rockchip/overlay/ directory
#   3. appends it to U_BOOT_FDT_OVERLAYS in /etc/default/u-boot (preserving any
#      overlays already registered, so it is safe to call once per overlay)

set -eE
trap 'echo "Error: in $0 on line $LINENO"' ERR

writable="$1"
dts="$2"

if [ -z "${writable}" ] || [ ! -d "${writable}" ]; then
    echo "Error: writable root '${writable}' does not exist"
    exit 1
fi
if [ -z "${dts}" ] || [ ! -f "${dts}" ]; then
    echo "Error: overlay source '${dts}' not found"
    exit 1
fi
if ! command -v dtc > /dev/null; then
    echo "Error: dtc (device-tree-compiler) is required but not installed"
    exit 1
fi

name="$(basename "${dts%.dts}")"
boot="${writable}/boot/firmware"
overlay_ref="device-tree/rockchip/overlay/${name}.dtbo"
overlay_dir="${boot}/device-tree/rockchip/overlay"

# The kernel ships its overlays under <boot>/device-tree/rockchip/overlay
# (device-tree is a symlink to the current kernel's dtb dir). If that layout is
# not present, discover an existing overlay dir and reference by relative path.
if [ ! -e "${boot}/device-tree" ]; then
    found="$(find "${boot}" -type d -path '*rockchip/overlay' 2>/dev/null | head -n1)"
    if [ -z "${found}" ]; then
        echo "Error: could not locate a device-tree overlay directory under ${boot}"
        exit 1
    fi
    overlay_dir="${found}"
    overlay_ref="${found#"${boot}"/}/${name}.dtbo"
fi
mkdir -p "${overlay_dir}"

echo "Installing device-tree overlay -> ${overlay_dir}/${name}.dtbo"
# -@ keeps the __symbols__/__fixups__ needed to resolve the &phandle references
# against the base device tree when u-boot applies the overlay.
dtc -@ -I dts -O dtb -o "${overlay_dir}/${name}.dtbo" "${dts}"

# Register the overlay in /etc/default/u-boot so u-boot-update emits an
# `fdtoverlays` entry. Preserve any overlays already configured (idempotent).
defaults="${writable}/etc/default/u-boot"
if [ ! -f "${defaults}" ]; then
    echo "Error: ${defaults} not found (cannot register the overlay)"
    exit 1
fi

current="$(sed -n -E 's/^[[:space:]]*U_BOOT_FDT_OVERLAYS="?([^"]*)"?.*/\1/p' "${defaults}" | head -n1)"
case " ${current} " in
    *" ${overlay_ref} "*) merged="${current}" ;;
    *)                    merged="${current:+${current} }${overlay_ref}" ;;
esac

sed -i -E '/^[[:space:]]*#?[[:space:]]*U_BOOT_FDT_OVERLAYS=/d' "${defaults}"
echo "U_BOOT_FDT_OVERLAYS=\"${merged}\"" >> "${defaults}"

echo "Registered overlay in ${defaults}: U_BOOT_FDT_OVERLAYS=\"${merged}\""
