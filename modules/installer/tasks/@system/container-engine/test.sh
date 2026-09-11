# The command exists and, where there is a daemon, something will start it.
debugging && return 0

arch-chroot "$MNT" command -v "$ARCH_OS_CONTAINER_ENGINE" >/dev/null
[ "$ARCH_OS_CONTAINER_ENGINE" != "docker" ] ||
    arch-chroot "$MNT" systemctl is-enabled docker.socket >/dev/null
