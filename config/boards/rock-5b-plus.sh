# shellcheck shell=bash

export BOARD_NAME="Radxa ROCK 5B Plus"
export BOARD_MAKER="Radxa"
export BOARD_SOC="Rockchip RK3588"
export BOARD_CPU="ARM Cortex A76 / A55"
export UBOOT_PACKAGE="u-boot-radxa-rk3588"
export UBOOT_RULES_TARGET="rock-5b-plus-rk3588"
export COMPATIBLE_SUITES=("noble")
export COMPATIBLE_FLAVORS=("server")

function config_image_hook__rock-5b-plus() {
    local rootfs="$1"
    local overlay="$2"
    local suite="$3"

    if [ "${suite}" == "noble" ]; then
        # Install panfork
        chroot "${rootfs}" add-apt-repository -y ppa:jjriek/panfork-mesa
        chroot "${rootfs}" apt-get update
        chroot "${rootfs}" apt-get -y install mali-g610-firmware
        chroot "${rootfs}" apt-get -y dist-upgrade

        # Install libmali blobs alongside panfork
        chroot "${rootfs}" apt-get -y install libmali-g610-x11

        # Install the rockchip camera engine
        chroot "${rootfs}" apt-get -y install camera-engine-rkaiq-rk3588

        # Fix and configure audio device
        mkdir -p "${rootfs}/usr/lib/scripts"
        cp "${overlay}/usr/lib/scripts/alsa-audio-config" "${rootfs}/usr/lib/scripts/alsa-audio-config"
        cp "${overlay}/usr/lib/systemd/system/alsa-audio-config.service" "${rootfs}/usr/lib/systemd/system/alsa-audio-config.service"
        chroot "${rootfs}" systemctl enable alsa-audio-config
    fi

    return 0
}

# Runs in build-image.sh after the rootfs is laid down on the image and
# right before u-boot-update, with $1 = the mounted writable root.
function build_image_hook__rock-5b-plus() {
    local writable="$1"

    # Fix HDMI-in audio capture (issue #1057): the stock device tree binds
    # the HDMI-RX sound card to a DUMMY codec, so there is no input. Apply a
    # device-tree overlay that rebinds it to the real hdmirx controller.
    local here
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    "${here}/../../scripts/fix-hdmiin-audio.sh" "${writable}"

    return 0
}
