# The image against the checksum published beside it. The checksum names the
# image itself, so run from the folder both are in this is the check anybody
# would run by hand.

simulating && return 0

if (cd "$(download_dir)" && sha256sum -c "$(basename "$(checksum)")"); then
    echo "checksum is correct"
    return 0
fi

# Both are thrown away rather than kept, so the next run fetches them again
# instead of finding the broken one and skipping the download. Both, because
# which of the two is wrong is exactly what a mismatch does not say.
rm -f "$(image)" "$(checksum)"
echo "$(basename "$(image)") could not be verified and was discarded with its checksum, please run this again" >&2
exit 1
