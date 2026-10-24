# Package choice: docs/REFERENCE.md
# https://wiki.archlinux.org/title/Installation_guide#Install_essential_packages

# sudo: base-devel brings it only with the AUR. mkinitcpio: the kernel takes the
# first initramfs provider pacman lists, and the bootloader task configures
# mkinitcpio. dosfstools: systemd checks the EFI partition, which boot counting
# writes at every boot.
packages=("$KERNEL" base sudo mkinitcpio zram-generator networkmanager btrfs-progs snapper dosfstools)

# A guest needs firmware only for a passed-through GPU. Many laptops load their
# sound firmware from sof-firmware, which linux-firmware leaves out.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ] || [ -n "$(graphics_cards)" ]; then
    packages+=(linux-firmware sof-firmware wireless-regdb)
else
    echo "virtual machine without a GPU of its own, skipping linux-firmware"
fi

# base ships no editor, no manuals and no ssh client.
packages+=("$ARCH_OS_EDITOR" man-db man-pages openssh)

ucode="$(microcode)"
[ -n "$ucode" ] && packages+=("$ucode")
secure_boot_wanted && packages+=(sbctl)

# Before pacstrap: the kernel install builds an initramfs whose sd-vconsole hook
# reads this file.
mkdir -p "${MNT}/etc"
echo "KEYMAP=$(vconsole_keymap)" >"${MNT}/etc/vconsole.conf"
font="$(resolved "$ARCH_OS_VCONSOLE_FONT" auto_font)"
if [ -n "$font" ]; then
    echo "FONT=${font}" >>"${MNT}/etc/vconsole.conf"
fi

# The longest download, the most likely to hit a stalling mirror.
installed=false
for ((i = 1; i <= RETRIES; i++)); do
    [ "$i" -gt 1 ] && echo "retry ${i}/${RETRIES}: pacstrap"
    if pacstrap -K "$MNT" "${packages[@]}"; then
        installed=true
        break
    fi
    sleep "$RETRY_WAIT"
done
if [ "$installed" != "true" ]; then
    echo "installing the base system failed after ${RETRIES} attempts" >&2
    check_online || exit "$EXIT_OFFLINE"
    exit 1
fi

genfstab -U "$MNT" >>"${MNT}/etc/fstab"
