# The command exists and, where there is a daemon, something will start it.
debugging && return 0

has_command "$ARCH_OS_CONTAINER_ENGINE"
[ "$ARCH_OS_CONTAINER_ENGINE" != "docker" ] ||
    arch-chroot "$MNT" systemctl is-enabled docker.socket >/dev/null
