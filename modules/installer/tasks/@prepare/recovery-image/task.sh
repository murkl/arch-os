# The Recovery image at hand before the disk stage sizes a partition after it.
# The Arch OS ISO carries it; any other live image fetches it from the release
# this Installer belongs to, held to the checksum GitHub publishes for it. Here
# rather than beside the partition: a download that fails should fail while
# the disk is still untouched.

if [ -f "${RECOVERY_IMAGE}/recovery.img" ] && [ -f "${RECOVERY_IMAGE}/recovery.efi" ]; then
    echo "the Recovery image is at ${RECOVERY_IMAGE}"
    return 0
fi

read -r url digest <<<"$(release_asset -recovery-x86_64.tar)"
if [ -z "$url" ] || [ -z "$digest" ]; then
    echo "The release v${VERSION} is out of reach or holds no Recovery image with a checksum. Connect this machine, or turn Recovery off in the settings." >&2
    exit 1
fi

download="${RECOVERY_IMAGE}.tar"
echo "fetching ${url##*/}"
if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "$download"; then
    rm -f "$download"
    echo "Downloading ${url##*/} failed. Start the installation again, or turn Recovery off in the settings." >&2
    exit 1
fi
if ! echo "${digest}  ${download}" | sha256sum -c - >/dev/null; then
    rm -f "$download"
    echo "${url##*/} does not match the checksum its release publishes and was thrown away. Start the installation again." >&2
    exit 1
fi

# Unpacked beside and moved into place whole, so what lies at RECOVERY_IMAGE is
# always a Recovery that arrived and matched - which is what lets a second run
# take it as it finds it.
rm -rf "${RECOVERY_IMAGE}.part"
mkdir -p "${RECOVERY_IMAGE}.part"
tar -xf "$download" -C "${RECOVERY_IMAGE}.part" --strip-components=1
rm -f "$download"
rm -rf "$RECOVERY_IMAGE"
mv "${RECOVERY_IMAGE}.part" "$RECOVERY_IMAGE"
echo "the Recovery image is at ${RECOVERY_IMAGE}"
