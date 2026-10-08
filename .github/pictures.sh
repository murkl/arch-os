#!/usr/bin/env bash
# The pictures in docs/ for a pull request, at the release it leads to, where it
# changes what they show or that release.
#
#   .github/pictures.sh <branch>
#
# The checkout is the pull request's merge commit, two deep: the one its run
# checked. The pictures are committed on top of it and pushed onto the branch,
# a fast-forward that takes main along, so they cannot conflict with main's.
#
# TITLE is the pull request's. GH_TOKEN pushes, GITHUB_TOKEN fetches the
# runtime. The commit pushed goes to GITHUB_OUTPUT as sha.
set -euo pipefail

branch="$1"

RELEASE_BRANCH=release-please--branches--main

version_of() { sed -n 's/^version:[[:space:]]*//p'; }

# How far b is above a: 3 a major, 2 a minor, 1 a patch, 0 not at all.
above() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        split(a, x, "."); split(b, y, ".")
        for (i = 1; i <= 3; i++) if (x[i] != y[i]) { print (y[i] > x[i]) ? 4 - i : 0; exit }
        print 0
    }'
}

raise() {
    awk -v a="$1" -v level="$2" 'BEGIN {
        split(a, x, ".")
        if (level == 3) print x[1] + 1 ".0.0"
        else if (level == 2) print x[1] "." x[2] + 1 ".0"
        else if (level == 1) print x[1] "." x[2] "." x[3] + 1
        else print a
    }'
}

# The level a title raises the next release by, read as release-please reads
# the commit it becomes: docs/CONTRIBUTING.md#the-title
title_level() {
    if [[ "$1" =~ ^[a-z]+(\([^\)]+\))?!: ]]; then
        echo 3
    elif [[ "$1" =~ ^feat(\([^\)]+\))?: ]]; then
        echo 2
    elif [[ "$1" =~ ^(fix|perf|revert)(\([^\)]+\))?: ]]; then
        echo 1
    else
        echo 0
    fi
}

# The version on the open release pull request, or nothing where none is open.
pending() {
    local status=0
    git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null || status=$?
    case "$status" in
    0) git fetch -q --depth=1 origin "$RELEASE_BRANCH" && git show FETCH_HEAD:oak.yaml | version_of ;;
    2) ;;
    *) return "$status" ;;
    esac
}

head="$(git rev-parse HEAD^2)"
last="$(version_of <oak.yaml)"
next="$(pending)"
[ -n "$next" ] && [ "$(above "$last" "$next")" -gt 0 ] || next="$last"

# main's pictures show the next release, and this pull request may raise it.
version="$next"
own="$(title_level "${TITLE:?}")"
[ "$own" -le "$(above "$last" "$next")" ] || version="$(raise "$last" "$own")"

# What the pages and the banner are drawn from.
status=0
git diff --quiet HEAD^1 HEAD -- oak.yaml oak.sh Makefile \
    docs/banner.py docs/screenshots.py docs/screenshots.yaml docs/logo.svg \
    ':(glob)modules/*/module.yaml' ':(glob)modules/*/locales/*.po' \
    ':(glob)modules/*/tasks/**/task.yaml' ':(glob)modules/*/actions/*/action.yaml' || status=$?
case "$status" in
0)
    if [ "$version" = "$next" ]; then
        echo "This pull request changes nothing the pictures show, and leaves the next release at ${next}"
        exit 0
    fi
    ;;
1) ;;
*) exit "$status" ;;
esac
echo "Rendering the pictures for ${branch} at ${version}"

# An Arch container booted with systemd: the pages list what localectl and
# timedatectl answer, and both refuse to run without systemd as PID 1. The
# host's network, and with it the host's resolver: a container's own is one more
# thing that can fail before the first download. Shared memory the size a
# machine has: chromium keeps its images there and stalls in docker's 64M.
container="$(docker run --detach --rm --privileged --cgroupns=host --network host --shm-size=1g \
    --volume /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp:exec \
    --volume "${PWD}:/repo" --workdir /repo archlinux:latest /usr/lib/systemd/systemd)"
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
docker exec "$container" pacman -Syu --noconfirm glibc
docker exec "$container" pacman -S --needed --noconfirm make curl kbd terminus-font tzdata \
    xkeyboard-config chromium imagemagick python-pyte python-yaml ttf-firacode-nerd

# Only the install is root's: what is rendered belongs to whoever runs this.
as_owner=(--user "$(id -u):$(id -g)" --env HOME=/tmp)

# A container leaves chromium no namespaces to sandbox itself in, and what it
# renders are pages made right here. Arch's chromium reads its flags from this
# file.
docker exec "${as_owner[@]}" "$container" sh -c 'mkdir -p ~/.config && echo --no-sandbox >~/.config/chromium-flags.conf'

docker exec "${as_owner[@]}" --env GITHUB_TOKEN "$container" make docs VERSION="$version"

git add docs/banner.png docs/screenshots/*.png
if git diff --cached --quiet; then
    echo "The pictures are these already"
    exit 0
fi

# A bot's push opens runs that wait for an approval; [skip ci] opens none, and
# the commit is cleared by the run that pushed it.
git -c user.name='github-actions[bot]' \
    -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit -q -m "docs: the pictures at ${version}" -m "[skip ci]"

# The token reaches git through its environment, never its command line. A
# branch that moved on meanwhile has a newer run, which renders its own.
if ! GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
    GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN:?}" | base64 -w0)" \
    git push origin "HEAD:refs/heads/${branch}"; then
    now="$(git ls-remote origin "refs/heads/${branch}" | cut -f1)"
    [ "$now" != "$head" ] || exit 1
    echo "${branch} moved on to ${now}, whose run renders its own pictures"
    exit 0
fi
echo "sha=$(git rev-parse HEAD)" >>"${GITHUB_OUTPUT:-/dev/null}"
