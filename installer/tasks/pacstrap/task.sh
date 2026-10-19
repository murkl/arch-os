# The packages the system is made of, and the file system table. What is here
# and what is not: docs/REFERENCE.md
# https://wiki.archlinux.org/title/Installation_guide#Install_essential_packages

# sudo outright: base-devel brings it only where the AUR is wanted. mkinitcpio
# outright: the kernel takes whichever initramfs provider pacman lists first,
# and the boot loader task writes mkinitcpio's configuration. dosfstools, so
# systemd checks the EFI partition at every boot, which the boot counting
# writes to at every boot.
packages=("$KERNEL" base sudo mkinitcpio zram-generator networkmanager btrfs-progs snapper dosfstools)

# Firmware is for hardware, and a guest has none but a card handed through to it.
# Many laptops' sound loads its firmware from sof-firmware, which linux-firmware
# leaves out.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ] || [ -n "$(graphics_cards)" ]; then
    packages+=(linux-firmware sof-firmware wireless-regdb)
else
    echo "a virtual machine with no card of its own: leaving out linux-firmware"
fi

# Interrupts spread over the cores. A guest's kernel refuses every affinity
# irqbalance sets and logs each refusal.
[ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ] && packages+=(irqbalance)

# base ships no editor, no manuals and no ssh client.
packages+=("$ARCH_OS_EDITOR" man-db man-pages openssh)

ucode="$(microcode)"
[ -n "$ucode" ] && packages+=("$ucode")
secure_boot_wanted && packages+=(sbctl)

# Before the packages: installing the kernel builds a ram disk, and its
# sd-vconsole hook reads this file.
mkdir -p "${MNT}/etc"
echo "KEYMAP=$(vconsole_keymap)" >"${MNT}/etc/vconsole.conf"
font="$(resolved "$ARCH_OS_VCONSOLE_FONT" auto_font)"
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
    check_online || exit "$EXIT_OFFLINE"
    exit 1
fi

genfstab -U "$MNT" >>"${MNT}/etc/fstab"
