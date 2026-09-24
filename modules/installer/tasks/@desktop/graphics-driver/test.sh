# What was installed depends on the cards, so this asks the same question the
# task did. Every driver is checked by what an application finds: the Vulkan
# driver's manifest, and for NVIDIA the module in the image the firmware starts.

[ -n "$(arch-chroot "$MNT" pacman -Qq mesa)" ]

while IFS=$'\t' read -r vendor device; do
    case "$vendor" in
    intel) [ -f "${MNT}/usr/share/vulkan/icd.d/intel_icd.json" ] ;;
    amd) [ -f "${MNT}/usr/share/vulkan/icd.d/radeon_icd.json" ] ;;
    nvidia)
        if ((device < 0x1e00)); then
            [ -f "${MNT}/usr/share/vulkan/icd.d/nouveau_icd.json" ]
            continue
        fi
        has_command nvidia-smi
        # The listing is read whole: grep stops at the first match, and
        # lsinitcpio, still writing, would die of that and fail the test under
        # pipefail.
        while read -r image; do
            contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
            grep -q '/nvidia-drm\.ko' <<<"$contents"
        done < <(boot_images)
        ;;
    esac
done < <(graphics_cards)
