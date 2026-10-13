# The image against the checksum the release page prints under the download.
# No test.sh: it would read the image against the checksum, which is this.

if [ ! -s "$(checksum)" ]; then
    echo "there is no published checksum for v$(release_version) to hold $(basename "$(image)") to" >&2
    exit 10
fi

if (cd "$(download_dir)" && sha256sum -c "$(basename "$(checksum)")"); then
    echo "checksum is correct"
    return 0
fi

# Thrown away, so the next run fetches it rather than skipping the download.
rm -f "$(image)"
echo "$(basename "$(image)") does not match its checksum and was discarded" >&2
exit 11
