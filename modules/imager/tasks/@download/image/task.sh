# The image of the release oak.yaml names, kept in the download folder so a
# second run costs nothing, and beside it the checksum that release publishes.

folder="$(download_dir)"
if ! mkdir -p "$folder" || [ ! -w "$folder" ]; then
    echo "${folder} cannot be created or written to" >&2
    exit 10
fi

# Unchecked, the image already here is all there is to it.
if [ "$ARCH_OS_IMAGE_VERIFY" != "true" ] && [ -f "$(image)" ]; then
    echo "$(image) is already here, and goes to the device unchecked"
    return 0
fi

# The checksum as the release publishes it now, not when an earlier run came.
check_online || exit "$EXIT_OFFLINE"
json="$(release_json "tags/v$(release_version)")" || exit "$EXIT_UNREACHABLE"
read -r url digest <<<"$(asset_in .iso <<<"$json")"
rm -f "$(checksum)"
if [ -n "$digest" ]; then
    printf '%s  %s\n' "$digest" "$(basename "$(image)")" >"$(checksum)"
fi

if [ -f "$(image)" ]; then
    echo "$(image) is already here"
    return 0
fi

if [ -z "$url" ]; then
    echo "the release v$(release_version) holds no image" >&2
    exit 1
fi

# Into a .part first, so a file that is there arrived whole.
echo "fetching ${url##*/}"
if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "$(image).part"; then
    rm -f "$(image).part"
    check_online || exit "$EXIT_OFFLINE"
    echo "downloading ${url##*/} into ${folder} failed" >&2
    exit 11
fi
mv "$(image).part" "$(image)"
echo "$(image) is here"
