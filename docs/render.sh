#!/usr/bin/env bash
# The pictures in docs/, rendered in an Arch container booted with systemd, so
# none of them depends on the machine that took it. The pages list what
# localectl and timedatectl answer, and both need systemd as PID 1. `make docs`
# runs it, and the release runs `make docs`.
#
#   docs/render.sh <repository>
set -euo pipefail

repo="$(realpath "$1")"

# Upgraded below, like every container CI runs.
image=archlinux:latest
packages=(make curl kbd terminus-font tzdata xkeyboard-config chromium imagemagick python-pyte python-yaml ttf-firacode-nerd)

# An Arch machine's own mirrors and packages where this runs on one: ranked for
# where it stands, unlike the image's, and most of what is installed below is
# in its cache already. Read only.
host=()
cache=()
if [ -f /etc/pacman.d/mirrorlist ]; then
    host=(--volume /etc/pacman.d/mirrorlist:/etc/pacman.d/mirrorlist:ro --volume /var/cache/pacman/pkg:/var/cache/pacman/host:ro)
    cache=(--cachedir /var/cache/pacman/pkg --cachedir /var/cache/pacman/host)
fi

# The host's network, and with it the host's resolver: a container's own is one
# more thing that can fail before the first download. Shared memory the size a
# machine has: chromium keeps its images there and stalls in docker's 64M.
container="$(docker run --detach --rm --privileged --cgroupns=host --network host --shm-size=1g \
    --volume /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp:exec "${host[@]}" \
    --volume "${repo}:/repo" --workdir /repo "$image" /usr/lib/systemd/systemd)"
trap 'docker stop "$container" >/dev/null' EXIT

state=""
for _ in $(seq 60); do
    state="$(docker exec "$container" systemctl is-system-running 2>/dev/null || true)"
    case "$state" in running | degraded) break ;; esac
    sleep 1
done
case "$state" in
running | degraded) ;;
*)
    echo "the container did not come up: ${state:-no answer from systemd}" >&2
    exit 1
    ;;
esac

# The image leaves out files an installed system has, the locales glibc
# supports among them, and a page lists what the machine has.
docker exec "$container" sed -i '/^NoExtract/d' /etc/pacman.conf
docker exec "$container" pacman -Syu --noconfirm "${cache[@]}" glibc
docker exec "$container" pacman -S --needed --noconfirm "${cache[@]}" "${packages[@]}"

# Only the install is root's: what is rendered belongs to whoever runs this.
as_owner=(--user "$(id -u):$(id -g)" --env HOME=/tmp)

# A container leaves chromium no namespaces to sandbox itself in, and what it
# renders are pages made right here. Arch's chromium reads its flags from this
# file.
docker exec "${as_owner[@]}" "$container" sh -c 'mkdir -p ~/.config && echo --no-sandbox >~/.config/chromium-flags.conf'

docker exec "${as_owner[@]}" --env GITHUB_TOKEN "$container" make screenshots banner
