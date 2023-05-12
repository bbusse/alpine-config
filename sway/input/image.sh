#!/bin/sh

DISPLAY_CONTROLLER_URL=https://raw.githubusercontent.com/opsboost/iss-display-controller/main
PYTHON_WAYLAND_VERSION=latest
PYTHON_WAYLAND_ARCHIVE=python-wayland-${PYTHON_WAYLAND_VERSION}.tar.xz
PYTHON_WAYLAND_URL=https://github.com/bbusse/python-wayland/releases/download/latest/${PYTHON_WAYLAND_ARCHIVE}
SWAY_CONFIG_URL=https://raw.githubusercontent.com/bbusse/swayvnc/main/config
SERVICE_USER=iss
PAYLOAD="mpv /home/${SERVICE_USER}/video.mp4"
STREAMS_PLAYLIST_URL="https://raw.githubusercontent.com/jnk22/kodinerds-iptv/master/iptv/clean/clean_tv.m3u"

setup_sway() {
    printf "Fetching sway config\n"
    curl --output-dir "${ROOTFS_PATH}"/etc/sway -LO "${SWAY_CONFIG_URL}"

    # Write Sway start script
    printf "Writing sway-launcher\n"
    sway_write_launcher

    # Write Sway openrc startup file
    printf "Writing openrc start script\n"
    mkdir -p "${ROOTFS_PATH}"/etc/local.d
    sway_write_start_script

    # Write exec to sway's config.d
    sway_configure_payload

    chmod +x "${ROOTFS_PATH}"/usr/bin/sway-launcher
    chmod +x "${ROOTFS_PATH}"/etc/local.d/sway.start
}

sway_configure_payload() {
    mkdir "${ROOTFS_PATH}"/etc/sway/config.d
    printf "exec %s" "${PAYLOAD}" >> "${ROOTFS_PATH}"/etc/sway/config.d/exec-payload
}

sway_write_launcher() {
cat << \EOF > "${ROOTFS_PATH}"/usr/bin/sway-launcher
#!/bin/sh

# Launch sway with a specific user, from a specific Virtual Terminal (vt)
# Two arguments are expected: a username (e.g., larry) and the id of a free vt (e.g., 7)

# Prepare the tty for the user
chown ${1} "/dev/tty${2}"
chmod 600 "/dev/tty${2}"

# Setup a clean environment for the user, take over the target vt, then launch sway as non-root user
su -l root -c "openvt -s -c ${2} -- su -l ${1} -c \"XDG_RUNTIME_DIR=/tmp WLR_LIBINPUT_NO_DEVICES=1 sway\""
EOF
}

sway_write_start_script() {
cat << EOF > "${ROOTFS_PATH}"/etc/local.d/sway.start
#!/bin/sh
sway-launcher ${SERVICE_USER} 2
EOF
}

main() {
    printf "Adding packages\n"
    chroot_exec apk add ffmpeg \
                        gstreamer \
                        gstreamer-tools \
                        gst-plugins-base \
                        gst-plugins-bad \
                        gst-plugins-good \
                        iw \
                        linux-firmware-cypress \
                        mesa-dri-gallium \
                        mpv \
                        py3-pip \
                        podman \
                        seatd \
                        sway \
                        wpa_supplicant \
                        xz

    # Build dependencies - we remove them again later
    chroot_exec apk add gcc \
                        git \
                        jpeg-dev \
                        libc-dev \
                        libffi-dev \
                        libxkbcommon-dev \
                        py3-wheel \
                        python3-dev \
                        zlib-dev \

    printf "Creating user\n"
    chroot_exec adduser --disabled-password ${SERVICE_USER}
    chroot_exec adduser ${SERVICE_USER} video
    chroot_exec adduser ${SERVICE_USER} seat

    # Enable services
    chroot_exec rc-update add seatd
    chroot_exec rc-update add wpa_supplicant

    # Add kernel modules to load
    cp /input/modules "${ROOTFS_PATH}"/etc/

    # Load device tree overlay
    echo "dtoverlay=vc4-kms-v3d" >> "${BOOTFS_PATH}"/config.txt

    setup_sway

     # Add display-controller for stream handling
    printf "Adding display-controller\n"
    curl -s -S --output-dir "${ROOTFS_PATH}/usr/bin" -LO "${DISPLAY_CONTROLLER_URL}/controller.py"
    curl -s -S --output-dir "${ROOTFS_PATH}/home/${SERVICE_USER}" -LO "${DISPLAY_CONTROLLER_URL}/requirements.txt"
    chroot_exec pip install -r /home/${SERVICE_USER}/requirements.txt
    chmod +x "${ROOTFS_PATH}"/usr/bin/controller.py

    # Add python-wayland
    printf "Adding python-wayland\n"
    mkdir -p "${ROOTFS_PATH}/usr/local/src"
    curl -s -S --output-dir "${ROOTFS_PATH}/usr/local/src/" -LO "${PYTHON_WAYLAND_URL}"
    chroot_exec cd /usr/local/src && tar xf "${PYTHON_WAYLAND_ARCHIVE}"

    # Remove build dependencies
    chroot_exec apk del gcc \
                        git \
                        jpeg-dev \
                        libc-dev \
                        libffi-dev \
                        libxkbcommon-dev \
                        py3-wheel \
                        python3-dev \
                        zlib-dev

    # Fetching streams playlist
    printf "Fetching streams playlist\n"
    curl -s -S --output-dir "${ROOTFS_PATH}"/home/${SERVICE_USER} -LO ${STREAMS_PLAYLIST_URL}
}

main "$@"
