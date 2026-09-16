# The image this program belongs to and the checksum published beside it, both
# onto this machine. Nothing here says the image is any good - that is the next
# step. This one is only ever about getting two files into the download folder.
#
# They are kept, so a second run - a wrong device, a stick pulled out halfway -
# costs the download only the first time, and a machine that has them needs no
# network at all. Which is what the preflight check promised.

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

# Whichever of the two is missing, and only that one. Each is written to a .part
# and moved into place afterwards, so a file that is there is a file that
# arrived whole - which is what makes skipping it safe.
#
# Retried, because the image is two gigabytes and a home connection drops one
# often enough that a run failing over it would be the usual outcome rather
# than the exception.
fetch() {
    url="$(asset_url "$1")"
    if [ -z "$url" ]; then
        echo "the release ${TAG} holds no ${1} file, and this machine has none" >&2
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
