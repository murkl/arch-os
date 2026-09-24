# The image against the checksum GitHub publishes for that release - the same
# one the release page prints under the download, so this is the check anybody
# would run by hand. The download put it beside the image.
#
# Where that release publishes none, nothing is written. Verify checksum off
# in the settings is the one way an image this project never published - one
# built here - reaches a device, and this step is then not run at all.

if [ ! -s "$(checksum)" ]; then
    echo "There is no published checksum for v${VERSION} to hold $(basename "$(image)") to, and it was not written. Turn Verify checksum off in the settings to write it unchecked." >&2
    exit 1
fi

if (cd "$(download_dir)" && sha256sum -c "$(basename "$(checksum)")"); then
    echo "checksum is correct"
    return 0
fi

# Thrown away rather than kept, so the next run fetches it again instead of
# finding the broken one and skipping the download.
rm -f "$(image)"
echo "$(basename "$(image)") could not be verified and was discarded, please run this again" >&2
exit 1
