# The image this program belongs to, on this machine and checked against the
# checksum published beside it.
#
# Both files are kept next to the program, so a second run - a wrong device, a
# stick pulled out halfway - costs the download only the first time, and a
# machine that has them needs no network at all. Which is what the preflight
# check promised.

simulating && return 0

target="$(image)"
name="${target##*/}"

# Whichever of the two is missing, and only that one. Each is written to a .part
# and moved into place afterwards, so a file that is there is a file that
# arrived whole - which is what makes skipping it safe.
fetch() {
    url="$(asset_url "$1")"
    if [ -z "$url" ]; then
        echo "the release ${TAG} holds no ${1} file, and this machine has none" >&2
        exit 1
    fi
    echo "fetching ${url##*/}"
    if ! curl -Lf --progress-bar "$url" -o "${2}.part"; then
        rm -f "${2}.part"
        echo "downloading ${url##*/} failed" >&2
        exit 1
    fi
    mv "${2}.part" "$2"
}

[ -f "${target}.sha256" ] || fetch .iso.sha256 "${target}.sha256"
[ -f "$target" ] || fetch .iso "$target"

# The checksum ships beside the image and names the file itself, so this is the
# check anybody would run by hand. An image that fails is thrown away rather
# than kept, so the next run fetches it again instead of finding the broken one
# and skipping the download.
if ! (cd "$HERE" && sha256sum -c "${name}.sha256" >/dev/null 2>&1); then
    rm -f "$target"
    echo "${name} is damaged and was discarded, please run this again" >&2
    exit 1
fi

echo "checksum is correct"
