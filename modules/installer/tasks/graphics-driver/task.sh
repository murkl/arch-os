# The graphics driver, and whatever else the card needs to start with the desktop
# rather than after it. Every branch rebuilds the ram disk directly rather than
# through pacman, which is why the Secure Boot signing comes after this one.

simulating && return 0

# The modules this card needs in the ram disk. A drop-in rather than an edit of
# /etc/mkinitcpio.conf, which belongs to the mkinitcpio package: it is read
# after the hooks the initramfs task set, and leaves nothing to merge after an
# update.
early_modules() {
    mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
    {
        echo '# Written by the Arch OS Installer.'
        echo "MODULES=($*)"
    } >"${MNT}/etc/mkinitcpio.conf.d/30-graphics.conf"
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
    # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
    mkdir -p "${MNT}/etc/modprobe.d"
    echo 'options nvidia_drm modeset=1 fbdev=1' >"${MNT}/etc/modprobe.d/nvidia.conf"
    early_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm

    # The modules live in the ram disk, so it is rebuilt whenever the driver or
    # the kernel changes: once per batch, not once per package.
    # https://wiki.archlinux.org/title/NVIDIA#pacman_hook
    mkdir -p "${MNT}/etc/pacman.d/hooks"
    {
        echo '[Trigger]'
        echo 'Operation=Install'
        echo 'Operation=Upgrade'
        echo 'Operation=Remove'
        echo 'Type=Package'
        echo "Target=${driver}"
        echo "Target=${ARCH_OS_KERNEL}"
        echo
        echo '[Action]'
        echo 'Description=Update the NVIDIA module in the initramfs'
        echo 'Depends=mkinitcpio'
        echo 'When=PostTransaction'
        echo 'NeedsTargets'
        echo "Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'"
    } >"${MNT}/etc/pacman.d/hooks/nvidia.hook"

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
