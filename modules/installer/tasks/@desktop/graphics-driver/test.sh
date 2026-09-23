# What was installed depends on the card, so this asks the same question the
# task did. Vulkan is the one thing every branch but nvidia installs under the
# same name; nvidia is checked by what makes it start with the desktop at all.

case "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" in
nvidia)
    has_command nvidia-smi
    [ -f "${MNT}/etc/pacman.d/hooks/nvidia.hook" ]
    # In the image the firmware starts, which is what early loading means.
    while read -r image; do
        arch-chroot "$MNT" lsinitcpio "$image" | grep -q '/nvidia-drm\.ko'
    done < <(boot_images)
    ;;
*)
    has_command vulkaninfo
    ;;
esac
