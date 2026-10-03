# Each driver by what an application finds: the Vulkan manifest, and for NVIDIA
# the module in the image the firmware starts.
[ -n "$(arch-chroot "$MNT" pacman -Qq mesa)" ]
has_command glxinfo
has_command vulkaninfo

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
        # Read whole: lsinitcpio, still writing, dies of a grep that stops.
        while read -r image; do
            contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
            grep -q '/nvidia-drm\.ko' <<<"$contents"
        done < <(boot_images)
        ;;
    esac
done < <(graphics_cards)
