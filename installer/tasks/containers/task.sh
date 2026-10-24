# https://wiki.archlinux.org/title/Docker
# https://wiki.archlinux.org/title/Podman

case "$ARCH_OS_CONTAINER_ENGINE" in

docker)
    # Nested subvolumes: images and volumes stay out of snapshots, and a
    # rollback keeps them. https://wiki.archlinux.org/title/Snapper
    for dir in docker containerd; do
        btrfs subvolume create "${MNT}/var/lib/${dir}" >/dev/null
    done
    chroot_pacman_install docker docker-buildx docker-compose

    # Docker opens published ports past firewalld, so with the firewall they
    # bind to localhost only. Logs rotate, which json-file never does.
    # https://docs.docker.com/engine/network/packet-filtering-firewalls/
    bind=0.0.0.0
    if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
        bind=127.0.0.1
    fi
    mkdir -p "${MNT}/etc/docker"
    render "$(where)/daemon.json" BIND="$bind" >"${MNT}/etc/docker/daemon.json"

    # Started at boot, so restart policies bring containers back. No docker
    # group, which is root without a password: docker runs through sudo.
    arch-chroot "$MNT" systemctl enable docker.service
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
