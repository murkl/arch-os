# https://wiki.archlinux.org/title/Docker
# https://wiki.archlinux.org/title/Podman

case "$ARCH_OS_CONTAINER_ENGINE" in

docker)
    chroot_pacman_install docker docker-buildx docker-compose

    # Socket activation: the daemon starts with the first command.
    arch-chroot "$MNT" systemctl enable docker.socket

    # Root-equivalent, but the account is in wheel already.
    arch-chroot "$MNT" usermod -aG docker "$ARCH_OS_USERNAME"
    ;;

podman)
    # podman-docker provides `docker` and points DOCKER_HOST at the socket
    # below. `podman compose` prefers docker-compose.
    chroot_pacman_install podman podman-docker docker-compose

    # --global: no session exists yet, and the socket is per account.
    arch-chroot "$MNT" systemctl --global enable podman.socket

    # Arch sets no search registry, so a short name such as `nginx` prompts.
    mkdir -p "${MNT}/etc/containers/registries.conf.d"
    render "$(where)/10-unqualified-search-registries.conf" \
        >"${MNT}/etc/containers/registries.conf.d/10-unqualified-search-registries.conf"

    # Silences the notices of the docker and compose wrappers.
    touch "${MNT}/etc/containers/nodocker"
    mkdir -p "${MNT}/etc/containers/containers.conf.d"
    render "$(where)/10-compose-warning-logs.conf" \
        >"${MNT}/etc/containers/containers.conf.d/10-compose-warning-logs.conf"
    ;;

esac
