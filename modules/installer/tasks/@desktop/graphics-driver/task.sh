# The graphics driver, and whatever else the card needs to start with the
# desktop rather than after it. Every branch rebuilds the ram disk directly
# rather than through pacman, which is why the Secure Boot signing comes after
# this one.

simulating && return 0

data="$(where)"

# The modules this card needs in the ram disk, as a drop-in read after the hooks
# the initramfs task set.
early_modules() {
    mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
    render "${data}/30-graphics.conf" MODULES="$*" >"${MNT}/etc/mkinitcpio.conf.d/30-graphics.conf"
}

case "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" in

mesa) # https://wiki.archlinux.org/title/OpenGL#Installation
    packages=(mesa mesa-utils vkd3d vulkan-tools)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-mesa-utils lib32-vkd3d)
    chroot_pacman_install "${packages[@]}"
    ;;

intel_i915) # https://wiki.archlinux.org/title/Intel_graphics#Installation
    packages=(vulkan-intel vkd3d intel-media-driver vulkan-tools)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-vulkan-intel lib32-vkd3d)
    chroot_pacman_install "${packages[@]}"
    early_modules i915
    arch-chroot "$MNT" mkinitcpio -P
    ;;

nvidia) # https://wiki.archlinux.org/title/NVIDIA#Installation
    # Arch dropped the closed driver. The precompiled nvidia-open exists for the
    # stock kernel alone; every other one needs the dkms package.
    driver=nvidia-open-dkms
    packages=("${ARCH_OS_KERNEL}-headers" nvidia-settings nvidia-utils opencl-nvidia vkd3d vulkan-tools)
    if [ "$ARCH_OS_KERNEL" = "linux" ]; then
        driver=nvidia-open
        packages=(nvidia-settings nvidia-utils opencl-nvidia vkd3d vulkan-tools)
    fi
    packages+=("$driver")
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-nvidia-utils lib32-opencl-nvidia lib32-vkd3d)
    chroot_pacman_install "${packages[@]}"

    # Kernel mode setting, without which Wayland does not start on this driver.
    # And the video memory the card holds over a suspend, which this driver
    # frees rather than saves unless told otherwise - the three units are what
    # do the saving, and nvidia-utils ships them switched off.
    # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
    # https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Preserve_video_memory_after_suspend
    mkdir -p "${MNT}/etc/modprobe.d"
    render "${data}/nvidia.conf" >"${MNT}/etc/modprobe.d/nvidia.conf"
    arch-chroot "$MNT" systemctl enable \
        nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
    early_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm

    # The modules live in the ram disk, so it is rebuilt whenever the driver or
    # the kernel changes - once per batch, not once per package.
    # https://wiki.archlinux.org/title/NVIDIA#pacman_hook
    mkdir -p "${MNT}/etc/pacman.d/hooks"
    render "${data}/nvidia.hook" DRIVER="$driver" KERNEL="$ARCH_OS_KERNEL" >"${MNT}/etc/pacman.d/hooks/nvidia.hook"

    # GDM refuses Wayland on this driver by default; the empty rule overrides it.
    # https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver
    mkdir -p "${MNT}/etc/udev/rules.d"
    [ -f "${MNT}/etc/udev/rules.d/61-gdm.rules" ] || ln -s /dev/null "${MNT}/etc/udev/rules.d/61-gdm.rules"

    arch-chroot "$MNT" mkinitcpio -P
    ;;

amd) # https://wiki.archlinux.org/title/AMDGPU#Installation
    packages=(mesa mesa-utils vulkan-radeon vkd3d vulkan-tools vulkan-mesa-layers opencl-mesa)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] &&
        packages+=(lib32-mesa lib32-vulkan-radeon lib32-vkd3d lib32-vulkan-mesa-layers lib32-opencl-mesa)
    chroot_pacman_install "${packages[@]}"
    early_modules amdgpu
    arch-chroot "$MNT" mkinitcpio -P
    ;;

ati) # https://wiki.archlinux.org/title/ATI#Installation
    packages=(mesa mesa-utils vkd3d vulkan-tools vulkan-mesa-layers opencl-mesa)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] &&
        packages+=(lib32-mesa lib32-vkd3d lib32-vulkan-mesa-layers lib32-opencl-mesa)
    chroot_pacman_install "${packages[@]}"
    early_modules radeon
    arch-chroot "$MNT" mkinitcpio -P
    ;;

*)
    echo "unknown graphics driver: ${ARCH_OS_DESKTOP_GRAPHICS_DRIVER}" >&2
    exit 1
    ;;
esac
