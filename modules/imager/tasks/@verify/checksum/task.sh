# The image against the checksum GitHub publishes for that release - the same
# one the release page prints under the download, so this is the check anybody
# would run by hand.
#
# Where that release publishes none, there is nothing to hold the image to and
# the answer given a moment ago decides. That is the one way an image this
# project never published - one built here - reaches a device.

simulating && return 0

digest="$(image_asset | cut -d' ' -f2)"
if [ -z "$digest" ]; then
    if [ "$ARCH_OS_IMAGE_UNVERIFIED" = true ]; then
        echo "v${VERSION} publishes no checksum, $(basename "$(image)") goes to the device unchecked"
        return 0
    fi
    echo "There is no published checksum for v${VERSION} to hold $(basename "$(image)") to, and it was not written." >&2
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
