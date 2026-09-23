# The command is there, and so is what the first container needs: something to
# start the engine, and somewhere to look for an image named without a registry.

has_command "$ARCH_OS_CONTAINER_ENGINE"

case "$ARCH_OS_CONTAINER_ENGINE" in
docker)
    arch-chroot "$MNT" systemctl is-enabled docker.socket >/dev/null
    ;;
podman)
    arch-chroot "$MNT" systemctl --global is-enabled podman.socket >/dev/null
    grep -q '^unqualified-search-registries' \
        "${MNT}/etc/containers/registries.conf.d/10-unqualified-search-registries.conf"
    ;;
esac
