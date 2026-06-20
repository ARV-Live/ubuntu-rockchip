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

        # Install additional runtime packages for the image. gstreamer1.0-rockchip1
        # comes from the jjriek rockchip-multimedia PPA configured above; the rest
        # are stock Ubuntu. (The request listed "alsa", which is not a real Ubuntu
        # package, so alsa-utils is installed instead.)
        chroot "${rootfs}" apt-get -y install \
            nodejs \
            gstreamer1.0-tools \
            gstreamer1.0-plugins-base \
            gstreamer1.0-plugins-good \
            gstreamer1.0-plugins-bad \
            gstreamer1.0-plugins-ugly \
            gstreamer1.0-libav \
            gstreamer1.0-rockchip1 \
            gstreamer1.0-alsa \
            network-manager \
            modemmanager \
            hostapd \
            nftables \
            v4l-utils \
            nginx \
            sqlite3 \
            alsa-utils

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

    # Apply device-tree overlays right before u-boot-update writes the extlinux
    # config. Each .dts is compiled to a .dtbo and registered in U_BOOT_FDT_OVERLAYS.
    local here overlays
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    overlays="${here}/../../scripts/overlays"

    # HDMI-in audio capture fix (issue #1057): rebinds the HDMI-RX sound card
    # off the DUMMY codec onto the real hdmirx controller.
    "${here}/../../scripts/install-dt-overlay.sh" "${writable}" "${overlays}/hdmiin-audio.dts"

    # Constant fan speed: pin the pwm-fan (fan0) cooling-levels high.
    "${here}/../../scripts/install-dt-overlay.sh" "${writable}" "${overlays}/fan-cooling.dts"

    return 0
}
