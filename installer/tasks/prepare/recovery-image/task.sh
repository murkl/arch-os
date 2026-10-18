# Here rather than beside the partition: a download that fails should fail
# while the disk is still untouched. The Arch OS ISO carries the image already.
image="$(recovery_image)"

# Held to its partition before the disk is touched.
fits() {
    local size
    size="$(stat -c %s "${image}/recovery.img")"
    [ "$size" -le $((RECOVERY_MIB * 1048576)) ] && return 0
    echo "The Recovery image takes $((size / 1048576)) MiB, more than the ${RECOVERY_MIB} MiB of its partition." >&2
    return 1
}

if [ -f "${image}/recovery.img" ] && [ -f "${image}/recovery.efi" ]; then
    fits
    echo "the Recovery image is at ${image}"
    return 0
fi

check_online || exit "$EXIT_OFFLINE"
json="$(release_json "tags/${MODULE_VERSION}")" || exit "$EXIT_UNREACHABLE"
read -r url digest <<<"$(asset_in -recovery-x86_64.tar <<<"$json")"
if [ -z "$url" ] || [ -z "$digest" ]; then
    echo "the release ${MODULE_VERSION} holds no Recovery image with a checksum" >&2
    exit 1
fi

download="${image}.tar"
echo "fetching ${url##*/}"
if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "$download"; then
    rm -f "$download"
    check_online || exit "$EXIT_OFFLINE"
    echo "downloading ${url##*/} failed" >&2
    exit 10
fi
if ! echo "${digest}  ${download}" | sha256sum -c - >/dev/null; then
    rm -f "$download"
    echo "${url##*/} does not match the checksum its release publishes and was thrown away" >&2
    exit 11
fi

# Unpacked beside and moved into place whole, so what lies there is always a
# Recovery that arrived and matched, which a second run takes as it finds it.
rm -rf "${image}.part"
mkdir -p "${image}.part"
tar -xf "$download" -C "${image}.part" --strip-components=1
rm -f "$download"
rm -rf "$image"
mv "${image}.part" "$image"
fits
echo "the Recovery image is at ${image}"
