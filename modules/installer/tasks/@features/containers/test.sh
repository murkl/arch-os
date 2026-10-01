has_command "$ARCH_OS_CONTAINER_ENGINE"

case "$ARCH_OS_CONTAINER_ENGINE" in
docker)
    arch-chroot "$MNT" systemctl is-enabled docker.socket >/dev/null
    ;;
podman)
    arch-chroot "$MNT" systemctl --global is-enabled podman.socket >/dev/null
    grep -q '^unqualified-search-registries' \
        "${MNT}/etc/containers/registries.conf.d/10-unqualified-search-registries.conf"
    # Without a subordinate id range podman starts no rootless container.
    for file in subuid subgid; do
        grep -q "^${ARCH_OS_USERNAME}:" "${MNT}/etc/${file}"
    done
    ;;
esac
