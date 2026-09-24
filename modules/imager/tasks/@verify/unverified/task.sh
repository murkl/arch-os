# The answer to an image nothing can be held against, acted on at once: a no
# stops the run here, before anything is written.

if [ "$ARCH_OS_IMAGE_UNVERIFIED" != true ]; then
    echo "There is no published checksum for v${VERSION} to hold $(basename "$(image)") to, and it was not written." >&2
    exit 1
fi
echo "v${VERSION} publishes no checksum, $(basename "$(image)") goes to the device unchecked"
