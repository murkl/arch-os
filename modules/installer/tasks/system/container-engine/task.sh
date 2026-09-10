# One of the two container engines, each set up the way its Arch Wiki page
# describes. Neither is installed unless it was asked for.
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

    # The Wiki calls membership equivalent to root, and it is - but this
    # account is already in wheel and may sudo, so it gains nothing it did not
    # have. Without it every docker command asks for a password.
    arch-chroot "$MNT" usermod -aG docker "$ARCH_OS_USERNAME"
    ;;

podman)
    # No daemon and nothing to enable. podman-docker answers to `docker` on
    # the command line, podman-compose reads a compose file.
    chroot_pacman_install podman podman-docker podman-compose

    # The range of user ids a rootless container maps its own root onto.
    # useradd hands out none, and without them podman starts no container at
    # all. Only written when the account has no range yet, so a second one is
    # never appended.
    if ! grep -qs "^${ARCH_OS_USERNAME}:" "${MNT}/etc/subuid"; then
        arch-chroot "$MNT" usermod \
            --add-subuids 100000-165535 --add-subgids 100000-165535 "$ARCH_OS_USERNAME"
    fi
    ;;

esac
