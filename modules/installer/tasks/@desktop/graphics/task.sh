# The driver for every card in this machine, read off it: Mesa for all, per
# vendor its Vulkan driver and video decoding, OpenCL for AMD and NVIDIA, and
# what games reach for.
# https://wiki.archlinux.org/title/Xorg#Driver_installation
# https://wiki.archlinux.org/title/Hardware_video_acceleration

packages=(mesa mesa-utils vulkan-tools vkd3d)
lib32=(lib32-mesa lib32-mesa-utils lib32-vkd3d)
nvidia=false
other=false

while IFS=$'\t' read -r vendor device; do
    case "$vendor" in
    intel)
        other=true
        packages+=(vulkan-intel intel-media-driver)
        lib32+=(lib32-vulkan-intel)
        ;;
    amd)
        other=true
        packages+=(vulkan-radeon vulkan-mesa-layers opencl-mesa)
        lib32+=(lib32-vulkan-radeon lib32-vulkan-mesa-layers lib32-opencl-mesa)
        ;;
    nvidia)
        # The open module drives Turing on, device IDs from 0x1e00; older cards
        # run on nouveau. https://wiki.archlinux.org/title/NVIDIA#Installation
        if ((device >= 0x1e00)); then
            nvidia=true
        else
            packages+=(vulkan-nouveau)
            lib32+=(lib32-vulkan-nouveau)
        fi
        ;;
    esac
done < <(graphics_cards)

if [ "$nvidia" = "true" ]; then
    # DKMS: a prebuilt module exists for the stock kernel alone.
    packages+=(nvidia-open-dkms "${KERNEL}-headers" nvidia-utils nvidia-settings opencl-nvidia libva-nvidia-driver)
    lib32+=(lib32-nvidia-utils lib32-opencl-nvidia)

    # Beside another card, prime-run hands a program to this one.
    # https://wiki.archlinux.org/title/PRIME
    [ "$other" = "true" ] && packages+=(nvidia-prime)
fi

[ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("${lib32[@]}")
mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sort -u)
chroot_pacman_install "${packages[@]}"

[ "$nvidia" = "true" ] || return 0

# nvidia-utils sets modeset and suspend itself; what is left is early loading,
# so GDM never starts on the firmware's framebuffer.
# https://wiki.archlinux.org/title/NVIDIA#Early_loading
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/30-graphics.conf" MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm" \
    >"${MNT}/etc/mkinitcpio.conf.d/30-graphics.conf"

# GDM refuses Wayland on this driver unless its rule is masked.
# https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver
mkdir -p "${MNT}/etc/udev/rules.d"
[ -f "${MNT}/etc/udev/rules.d/61-gdm.rules" ] || ln -s /dev/null "${MNT}/etc/udev/rules.d/61-gdm.rules"

arch-chroot "$MNT" mkinitcpio -P
