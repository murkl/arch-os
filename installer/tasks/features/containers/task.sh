# Each engine as its Wiki page sets it up, usable from the account right away.
# https://wiki.archlinux.org/title/Docker
# https://wiki.archlinux.org/title/Podman

case "$ARCH_OS_CONTAINER_ENGINE" in

docker)
    chroot_pacman_install docker docker-buildx docker-compose

    # The socket: the daemon starts with the first command that speaks to it.
    arch-chroot "$MNT" systemctl enable docker.socket

    # Root-equivalent, but this account is in wheel already.
    arch-chroot "$MNT" usermod -aG docker "$ARCH_OS_USERNAME"
    ;;

podman)
    # podman-docker answers to `docker` and points DOCKER_HOST at the socket
    # below; docker-compose is what `podman compose` reaches for first.
    chroot_pacman_install podman podman-docker docker-compose

    # --global: there is no session yet, and it belongs to whoever logs in.
    arch-chroot "$MNT" systemctl --global enable podman.socket

    # Arch searches no registry, so `nginx` without one stops on a question.
    mkdir -p "${MNT}/etc/containers/registries.conf.d"
    render "$(where)/10-unqualified-search-registries.conf" \
        >"${MNT}/etc/containers/registries.conf.d/10-unqualified-search-registries.conf"

    # The two notices the docker and compose wrappers print on stderr, off.
    touch "${MNT}/etc/containers/nodocker"
    mkdir -p "${MNT}/etc/containers/containers.conf.d"
    render "$(where)/10-compose-warning-logs.conf" \
        >"${MNT}/etc/containers/containers.conf.d/10-compose-warning-logs.conf"
    ;;

esac
