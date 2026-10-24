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
        # iHD decodes from Broadwell on, i965 before it. libva tries iHD first.
        packages+=(vulkan-intel intel-media-driver libva-intel-driver)
        lib32+=(lib32-vulkan-intel)
        ;;
    amd)
        other=true
        packages+=(vulkan-radeon vulkan-mesa-layers opencl-mesa)
        lib32+=(lib32-vulkan-radeon lib32-vulkan-mesa-layers lib32-opencl-mesa)
        ;;
    nvidia)
        # The open module drives Turing on, device IDs from 0x1e00. Older cards
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
    # DKMS: prebuilt modules exist for the stock kernel only.
    packages+=(nvidia-open-dkms "${KERNEL}-headers" nvidia-utils nvidia-settings opencl-nvidia libva-nvidia-driver)
    lib32+=(lib32-nvidia-utils lib32-opencl-nvidia)

    # Beside another GPU, prime-run offloads a program to this one.
    # https://wiki.archlinux.org/title/PRIME
    [ "$other" = "true" ] && packages+=(nvidia-prime)
fi

[ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("${lib32[@]}")
mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sort -u)
chroot_pacman_install "${packages[@]}"

[ "$nvidia" = "true" ] || return 0

# The driver sets modeset and keeps video memory over a suspend by itself. Early
# loading keeps GDM off the firmware's framebuffer.
# https://wiki.archlinux.org/title/NVIDIA#Early_loading
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/30-graphics.conf" MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm" \
    >"${MNT}/etc/mkinitcpio.conf.d/30-graphics.conf"

# NVIDIA alone: the kms hook goes, as the Wiki says, or nouveau lands in the
# image. Beside another GPU the hook stays for its driver, and nvidia-utils'
# modprobe.d file, carried in by modconf, blacklists nouveau.
if [ "$other" != "true" ]; then
    render "$(where)/31-nvidia-alone.conf" >"${MNT}/etc/mkinitcpio.conf.d/31-nvidia-alone.conf"
fi

arch-chroot "$MNT" mkinitcpio -P
