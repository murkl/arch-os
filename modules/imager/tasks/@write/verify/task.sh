# The image against the checksum the release page prints under the download.
# No test.sh: it would read the image against the checksum, which is this.

if [ ! -s "$(checksum)" ]; then
    echo "There is no published checksum for v$(release_version) to hold $(basename "$(image)") to, and it was not written. Turn Verify checksum off in the settings to write it unchecked." >&2
    exit 1
fi

if (cd "$(download_dir)" && sha256sum -c "$(basename "$(checksum)")"); then
    echo "checksum is correct"
    return 0
fi

# Thrown away, so the next run fetches it rather than skipping the download.
rm -f "$(image)"
echo "$(basename "$(image)") could not be verified and was discarded, please run this again" >&2
exit 1
