# The image of the release oak.yaml names, kept in the download folder so a
# second run costs nothing, and beside it the checksum that release publishes.

dir="$(download_dir)"
mkdir -p "$dir" || {
    echo "${dir} cannot be created" >&2
    exit 1
}
[ -w "$dir" ] || {
    echo "${dir} cannot be written to" >&2
    exit 1
}

# Unchecked, the image already here is all there is to it.
if [ "$ARCH_OS_IMAGE_VERIFY" != "true" ] && [ -f "$(image)" ]; then
    echo "$(image) is already here, and goes to the device unchecked"
    return 0
fi

# The checksum as the release publishes it now, not when an earlier run came.
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
    echo "The release v$(release_version) is out of reach and ${dir} holds no image. Connect this machine, or put arch-os-$(release_version)-x86_64.iso there yourself." >&2
    exit 1
fi

# Into a .part first, so a file that is there arrived whole.
echo "fetching ${url##*/}"
if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "$(image).part"; then
    rm -f "$(image).part"
    echo "downloading ${url##*/} into ${dir} failed" >&2
    exit 1
fi
mv "$(image).part" "$(image)"
echo "$(image) is here"
