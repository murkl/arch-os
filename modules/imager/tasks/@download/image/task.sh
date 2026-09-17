# The image this program belongs to and the checksum published beside it, both
# into the download folder. Whether the image is any good is the next step.
#
# Both are kept, so a second run costs the download only the first time - and a
# folder that already holds the pair needs no network and no release at all,
# which is what lets an image built by hand be written from here.

simulating && return 0

dir="$(download_dir)"
mkdir -p "$dir" || {
    echo "${dir} cannot be created" >&2
    exit 1
}
[ -w "$dir" ] || {
    echo "${dir} cannot be written to" >&2
    exit 1
}

if [ -f "$(image)" ] && [ -f "$(checksum)" ]; then
    echo "$(image) is already here"
    return 0
fi

# https even after a redirect, because -L would otherwise follow a 302 into
# plain http, where the answer can be anybody's - and a connect timeout, so a
# machine behind a black hole says so rather than hanging.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# The address of the one asset of this release whose name ends the given way,
# or nothing where the release cannot be reached. Matched on the ending rather
# than on the name, so renaming a download stays a change to the build.
#
# One awk rather than a pipeline of greps: finding nothing is an answer here and
# not a failure, which under pipefail is what grep would make of it.
tag="v${VERSION}"
json="$(fetch_url -s --max-time 20 "https://api.github.com/repos/murkl/arch-os/releases/tags/${tag}" || true)"
asset_url() {
    printf '%s\n' "$json" | awk -v suffix="$1" '
        match($0, /"browser_download_url": *"[^"]*"/) {
            url = substr($0, RSTART, RLENGTH)
            sub(/.*: *"/, "", url)
            sub(/"$/, "", url)
            if (substr(url, length(url) - length(suffix) + 1) == suffix) { print url; exit }
        }'
}

# Each is written to a .part and moved into place afterwards, so a file that is
# there is a file that arrived whole - which is what makes skipping it safe.
# Retried, because the image is two gigabytes and a home connection drops one
# often enough that a run failing over it would be the usual outcome.
fetch() {
    url="$(asset_url "$1")"
    if [ -z "$url" ]; then
        echo "The release ${tag} is out of reach and ${dir} holds no ${1} file. Connect this machine, or put the image and its checksum there yourself." >&2
        exit 1
    fi
    echo "fetching ${url##*/}"
    if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "${2}.part"; then
        rm -f "${2}.part"
        echo "downloading ${url##*/} into ${dir} failed" >&2
        exit 1
    fi
    mv "${2}.part" "$2"
}

[ -f "$(checksum)" ] || fetch .iso.sha256 "$(checksum)"
[ -f "$(image)" ] || fetch .iso "$(image)"

echo "$(image) is here"
