has_command "$ARCH_OS_CONTAINER_ENGINE"

case "$ARCH_OS_CONTAINER_ENGINE" in
docker)
    arch-chroot "$MNT" systemctl is-enabled docker.service >/dev/null
    arch-chroot "$MNT" dockerd --validate --config-file /etc/docker/daemon.json >/dev/null
    if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
        grep -q '"ip": "127.0.0.1"' "${MNT}/etc/docker/daemon.json"
    fi
    for dir in docker containerd; do
        btrfs subvolume show "${MNT}/var/lib/${dir}" >/dev/null
    done
    groups="$(arch-chroot "$MNT" id -nG "$ARCH_OS_USERNAME")"
    if [[ " ${groups} " == *" docker "* ]]; then
        echo "${ARCH_OS_USERNAME} is in the docker group, root without a password"
        exit 1
    fi
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
