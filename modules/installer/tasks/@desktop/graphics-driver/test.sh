# What was installed depends on the card, so this asks the same question the
# task did. Vulkan is the one thing every branch but nvidia installs under the
# same name; nvidia is checked by the files and units that make it work at all.
debugging && return 0

case "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" in
nvidia)
    has_command nvidia-smi
    [ -f "${MNT}/etc/modprobe.d/nvidia.conf" ]
    [ -f "${MNT}/etc/pacman.d/hooks/nvidia.hook" ]
    arch-chroot "$MNT" systemctl is-enabled \
        nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service >/dev/null
    ;;
*)
    has_command vulkaninfo
    ;;
esac
