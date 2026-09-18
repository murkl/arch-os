# The image against the checksum GitHub publishes for that release - the same
# one the release page prints under the download, so this is the check anybody
# would run by hand.

simulating && return 0

digest="$(image_asset | cut -d' ' -f2)"
if [ -z "$digest" ]; then
    echo "The release v${VERSION} is out of reach, so $(basename "$(image)") has nothing to be checked against. Connect this machine and run this again." >&2
    exit 1
fi

if echo "${digest}  $(basename "$(image)")" | (cd "$(download_dir)" && sha256sum -c -); then
    echo "checksum is correct"
    return 0
fi

# Thrown away rather than kept, so the next run fetches it again instead of
# finding the broken one and skipping the download.
rm -f "$(image)"
echo "$(basename "$(image)") could not be verified and was discarded, please run this again" >&2
exit 1
