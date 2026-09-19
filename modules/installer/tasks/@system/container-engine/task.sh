# One of the two container engines, each set up the way its Arch Wiki page
# describes, and each usable from the account this installation makes without
# anything further being read or configured. Neither is installed unless it was
# asked for.
#
# https://wiki.archlinux.org/title/Docker
# https://wiki.archlinux.org/title/Podman

simulating && return 0

case "$ARCH_OS_CONTAINER_ENGINE" in

docker)
    # buildx and compose are the two subcommands everything assumes `docker`
    # has; both are separate packages here.
    chroot_pacman_install docker docker-buildx docker-compose

    # The socket rather than the service: the daemon is started by the first
    # command that speaks to it and never runs on a machine that speaks to it
    # never. A container declared restart:always wants docker.service instead.
    arch-chroot "$MNT" systemctl enable docker.socket

    # Equivalent to root, as the Wiki says - but this account is already in
    # wheel and may sudo, so it gains nothing it did not have.
    arch-chroot "$MNT" usermod -aG docker "$ARCH_OS_USERNAME"
    ;;

podman)
    # No daemon and nothing running as root. podman-docker answers to `docker`
    # on the command line and points DOCKER_HOST at the socket below, so what
    # speaks the Docker API finds this engine. docker-compose rather than
    # podman-compose: it is the original implementation and the provider
    # `podman compose` reaches for first, and podman hands it the socket and
    # turns buildkit off for it without being asked.
    chroot_pacman_install podman podman-docker docker-compose

    # The socket that DOCKER_HOST names, and the one thing between a machine
    # with podman on it and one where compose works. --global rather than
    # --user: there is no session here to enable it in, and it belongs to
    # whoever logs in rather than to the account being made. A container
    # declared restart:always wants podman-restart.service on top, as one
    # under docker wants docker.service.
    arch-chroot "$MNT" systemctl --global enable podman.socket

    # Arch configures no registry to search, so an image named without one -
    # `nginx` rather than `docker.io/library/nginx` - resolves to nothing and
    # podman stops to ask a question no script is there to answer. Docker has
    # this built into the daemon and needs nothing.
    mkdir -p "${MNT}/etc/containers/registries.conf.d"
    echo 'unqualified-search-registries = ["docker.io"]' \
        >"${MNT}/etc/containers/registries.conf.d/10-unqualified-search-registries.conf"

    # Podman announces itself twice on the way through: once from the docker
    # wrapper, once from the compose one, both on stderr - which is where
    # whatever called them reads what went wrong. Each message names its own
    # switch, and with both thrown `docker compose version` prints what docker
    # would and nothing else.
    touch "${MNT}/etc/containers/nodocker"
    mkdir -p "${MNT}/etc/containers/containers.conf.d"
    printf '[engine]\ncompose_warning_logs = false\n' \
        >"${MNT}/etc/containers/containers.conf.d/10-compose-warning-logs.conf"

    # The range of user ids a rootless container maps its own root onto, and
    # without one podman starts no container at all. useradd has written one
    # since shadow 4.11.1-3, so this is for an account that arrived some other
    # way - and only where there is none yet, so a second range is never
    # appended to a user who already has theirs.
    if ! grep -qs "^${ARCH_OS_USERNAME}:" "${MNT}/etc/subuid"; then
        arch-chroot "$MNT" usermod \
            --add-subuids 100000-165535 --add-subgids 100000-165535 "$ARCH_OS_USERNAME"
    fi
    ;;

esac
