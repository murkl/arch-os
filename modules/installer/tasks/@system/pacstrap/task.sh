# The packages the system is made of, and the file system table. What is here
# and what is not: docs/REFERENCE.md
# https://wiki.archlinux.org/title/Installation_guide#Install_essential_packages

# sudo outright: base-devel brings it only where the AUR is wanted. mkinitcpio
# outright: the kernel takes whichever initramfs provider pacman lists first,
# and the boot loader task writes mkinitcpio's configuration.
packages=("$KERNEL" base sudo mkinitcpio zram-generator networkmanager btrfs-progs snapper)

# Firmware is for hardware; a guest has none but a card handed through to it.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ] || [ -n "$(graphics_cards)" ]; then
    packages+=(linux-firmware wireless-regdb)
else
    echo "a virtual machine with no card of its own: leaving out linux-firmware"
fi

# base ships no editor, no manuals and no ssh client.
packages+=("$ARCH_OS_EDITOR" man-db man-pages openssh)

ucode="$(microcode)"
[ -n "$ucode" ] && packages+=("$ucode")
secure_boot_wanted && packages+=(sbctl)

# Before the packages: installing the kernel builds a ram disk, and its
# sd-vconsole hook reads this file.
mkdir -p "${MNT}/etc"
echo "KEYMAP=$(vconsole_keymap)" >"${MNT}/etc/vconsole.conf"
font="$(vconsole_font)"
if [ -n "$font" ]; then
    echo "FONT=${font}" >>"${MNT}/etc/vconsole.conf"
fi

# The longest download, and the one most likely to meet a mirror that stops.
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
    exit 1
fi

genfstab -U "$MNT" >>"${MNT}/etc/fstab"

# The EFI partition holds the kernel and the signed image: root's alone.
sed -i '/\/boot/ {s/fmask=[0-9]\+/fmask=0077/g; s/dmask=[0-9]\+/dmask=0077/g}' "${MNT}/etc/fstab"
