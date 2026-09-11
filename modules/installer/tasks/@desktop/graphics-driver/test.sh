# What was installed depends on the card, so this asks the same question the
# task did. Vulkan is the one thing every branch but nvidia installs by the same
# name; nvidia is checked by the two files that make it work at all - kernel
# mode setting, without which Wayland does not start, and the hook that keeps
# the module in the ram disk after an update.
debugging && return 0

case "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" in
nvidia)
    has_command nvidia-smi
    [ -f "${MNT}/etc/modprobe.d/nvidia.conf" ]
    [ -f "${MNT}/etc/pacman.d/hooks/nvidia.hook" ]
    ;;
*)
    has_command vulkaninfo
    ;;
esac
