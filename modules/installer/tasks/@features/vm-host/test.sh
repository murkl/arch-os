has_command virsh
arch-chroot "$MNT" systemctl is-enabled libvirtd.socket >/dev/null
[ "$ARCH_OS_DESKTOP" = "none" ] || has_command virt-manager

# The desktop's JACK, not jack2, or GNOME's pipewire-jack stops on a conflict.
[ "$ARCH_OS_DESKTOP" = "none" ] || arch-chroot "$MNT" pacman -Q pipewire-jack >/dev/null
