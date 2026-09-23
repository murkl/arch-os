# The graphics driver, and whatever else the card needs to start with the
# desktop rather than after it. The open drivers need nothing in the ram disk
# beyond what the kms hook already puts there; NVIDIA's modules are not in the
# kernel tree that hook reads, so that branch rebuilds the ram disk itself -
# which is why the Secure Boot signing comes after this one.
# https://wiki.archlinux.org/title/Kernel_mode_setting#Early_KMS_start

data="$(where)"

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

    # Kernel mode setting and keeping video memory over a suspend need nothing
    # from here any more. nvidia-utils sets modeset and fbdev itself, and turns
    # on the kernel's suspend notifiers in its own modprobe.d file - which is
    # why its upgrade switches the three nvidia-suspend units off again rather
    # than on. What is left is early loading, so the display manager never
    # starts on the firmware's framebuffer before the card has a driver.
    # https://wiki.archlinux.org/title/NVIDIA#Early_loading
    mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
    render "${data}/30-graphics.conf" MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm" \
        >"${MNT}/etc/mkinitcpio.conf.d/30-graphics.conf"

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
    ;;

ati) # https://wiki.archlinux.org/title/ATI#Installation
    packages=(mesa mesa-utils vkd3d vulkan-tools vulkan-mesa-layers opencl-mesa)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] &&
        packages+=(lib32-mesa lib32-vkd3d lib32-vulkan-mesa-layers lib32-opencl-mesa)
    chroot_pacman_install "${packages[@]}"
    ;;

*)
    echo "unknown graphics driver: ${ARCH_OS_DESKTOP_GRAPHICS_DRIVER}" >&2
    exit 1
    ;;
esac
