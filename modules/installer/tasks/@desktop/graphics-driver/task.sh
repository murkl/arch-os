# The driver for every graphics card in this machine, read off the machine rather
# than asked: Mesa for all of them, for each vendor its Vulkan driver and video
# decoding, and OpenCL for AMD and NVIDIA. A laptop with two cards gets both
# drivers. Beside them what games reach for: vkd3d for Direct3D 12 under Wine,
# and glxinfo and vulkaninfo to see which card a program ended up on.
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
        # Video decoding for AMD is part of mesa.
        other=true
        packages+=(vulkan-radeon vulkan-mesa-layers opencl-mesa)
        lib32+=(lib32-vulkan-radeon lib32-vulkan-mesa-layers lib32-opencl-mesa)
        ;;
    nvidia)
        # NVIDIA's open module drives Turing and every generation after it -
        # the GTX 16 and RTX cards, device IDs from 0x1e00 on. Arch ships no
        # NVIDIA driver for the ones before, which run on nouveau, part of Mesa.
        # https://wiki.archlinux.org/title/NVIDIA#Installation
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
    # Built by DKMS against the headers: the prebuilt module exists for the stock
    # kernel alone.
    packages+=(nvidia-open-dkms "${KERNEL}-headers" nvidia-utils nvidia-settings opencl-nvidia libva-nvidia-driver)
    lib32+=(lib32-nvidia-utils lib32-opencl-nvidia)

    # Beside another card, that one drives the screen and prime-run hands a
    # program to the NVIDIA card. https://wiki.archlinux.org/title/PRIME
    [ "$other" = "true" ] && packages+=(nvidia-prime)
fi

[ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("${lib32[@]}")

# Two cards of one vendor name the same packages twice.
mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sort -u)
chroot_pacman_install "${packages[@]}"

[ "$nvidia" = "true" ] || return 0

# Kernel mode setting and keeping video memory over a suspend need nothing from
# here any more. nvidia-utils sets modeset and fbdev itself, and turns on the
# kernel's suspend notifiers in its own modprobe.d file. What is left is early
# loading, so the display manager never starts on the firmware's framebuffer
# before the card has a driver. mkinitcpio rebuilds the image on its own
# whenever the driver or the kernel changes.
# https://wiki.archlinux.org/title/NVIDIA#Early_loading
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/30-graphics.conf" MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm" \
    >"${MNT}/etc/mkinitcpio.conf.d/30-graphics.conf"

# GDM refuses Wayland on this driver by default; the empty rule overrides it.
# https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver
mkdir -p "${MNT}/etc/udev/rules.d"
[ -f "${MNT}/etc/udev/rules.d/61-gdm.rules" ] || ln -s /dev/null "${MNT}/etc/udev/rules.d/61-gdm.rules"

arch-chroot "$MNT" mkinitcpio -P
