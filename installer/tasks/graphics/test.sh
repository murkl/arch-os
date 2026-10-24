# Each driver by what applications load: the Vulkan manifest, both libva
# drivers for Intel, the NVIDIA module in every image.
[ -n "$(arch-chroot "$MNT" pacman -Qq mesa)" ]
has_command glxinfo
has_command vulkaninfo

# Another GPU beside NVIDIA, as the task detects it.
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
        # Read whole: a grep -q that exits early kills lsinitcpio by SIGPIPE.
        while read -r image; do
            contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
            grep -q '/nvidia-drm\.ko' <<<"$contents"
            # Alone, nouveau stays out of the image. Beside another GPU its
            # hook may bring nouveau, so the blacklist comes along.
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
