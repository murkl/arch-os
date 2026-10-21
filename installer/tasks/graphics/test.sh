# Each driver by what an application finds: the Vulkan manifest, for Intel both
# video drivers libva tries, and for NVIDIA the module in the image the firmware
# starts.
[ -n "$(arch-chroot "$MNT" pacman -Qq mesa)" ]
has_command glxinfo
has_command vulkaninfo

# Whether NVIDIA has another card beside it, as the task reads it.
other=false
while IFS=$'\t' read -r vendor _; do
    [ "$vendor" = nvidia ] || other=true
done < <(graphics_cards)

while IFS=$'\t' read -r vendor device; do
    case "$vendor" in
    intel)
        [ -f "${MNT}/usr/share/vulkan/icd.d/intel_icd.json" ]
        [ -f "${MNT}/usr/lib/dri/iHD_drv_video.so" ]
        [ -f "${MNT}/usr/lib/dri/i965_drv_video.so" ]
        ;;
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
            # Alone, nouveau is not in the image. Beside another card the
            # hook that brings that card's driver may bring nouveau, and the
            # file that keeps it from loading is in the image with it.
            if [ "$other" = "true" ]; then
                grep -q 'modprobe\.d/nvidia-utils\.conf' <<<"$contents"
            elif grep -q '/nouveau\.ko' <<<"$contents"; then
                echo "nouveau is in ${image} beside the NVIDIA driver" >&2
                exit 1
            fi
        done < <(boot_images)
        ;;
    esac
done < <(graphics_cards)
