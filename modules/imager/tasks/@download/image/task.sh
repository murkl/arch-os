# The image of the release oak.yaml names, into the download folder, and beside
# it what that release says it hashes to. Whether it does is the next step.
#
# It is kept, so a second run costs the download only the first time. A folder
# that already holds it is left alone here - what the file is held to is the
# next step's business, not where it came from.

dir="$(download_dir)"
mkdir -p "$dir" || {
    echo "${dir} cannot be created" >&2
    exit 1
}
[ -w "$dir" ] || {
    echo "${dir} cannot be written to" >&2
    exit 1
}

# Where the release keeps the image and what it hashes to, asked once. The
# checksum goes beside the image whether or not the image is fetched now, and an
# old one is taken away first: what the image is held to is what the release
# publishes at this moment, not what it published when an earlier run fetched it.
read -r url digest <<<"$(release_asset .iso)"
rm -f "$(checksum)"
if [ -n "$digest" ]; then
    printf '%s  %s\n' "$digest" "$(basename "$(image)")" >"$(checksum)"
fi

if [ -f "$(image)" ]; then
    echo "$(image) is already here"
    return 0
fi

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
