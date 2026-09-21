# The image this program belongs to, into the download folder. Whether it is any
# good is the next step.
#
# It is kept, so a second run costs the download only the first time. A folder
# that already holds it is left alone here - what the file is held to is the
# next step's business, not where it came from.

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

if [ -f "$(image)" ]; then
    echo "$(image) is already here"
    return 0
fi

url="$(image_asset | cut -d' ' -f1)"
if [ -z "$url" ]; then
    echo "The release v${VERSION} is out of reach and ${dir} holds no image. Connect this machine, or put arch-os-${VERSION}-x86_64.iso there yourself." >&2
    exit 1
fi

# Written to a .part and moved into place afterwards, so a file that is there is
# a file that arrived whole - which is what makes skipping it safe. Retried,
# because the image is two gigabytes and a home connection drops one often
# enough that a run failing over it would be the usual outcome.
echo "fetching ${url##*/}"
if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "$(image).part"; then
    rm -f "$(image).part"
    echo "downloading ${url##*/} into ${dir} failed" >&2
    exit 1
fi
mv "$(image).part" "$(image)"

echo "$(image) is here"
