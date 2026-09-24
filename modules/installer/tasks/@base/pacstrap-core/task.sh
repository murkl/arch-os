# The packages the system is made of, and the file system table.
# https://wiki.archlinux.org/title/Installation_guide#Install_essential_packages
#
# What is here and what is not: docs/REFERENCE.md

# sudo is named outright: it comes with base-devel, which only an installation
# that builds from the AUR needs, and the wheel rule is written either way.
packages=("$KERNEL" base sudo zram-generator networkmanager btrfs-progs snapper)

# Firmware is for hardware, and a guest has none. The exception is a card handed
# through to one.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ] || [ -n "$(graphics_cards)" ]; then
    packages+=(linux-firmware wireless-regdb)
else
    echo "a virtual machine with no card of its own: leaving out linux-firmware"
fi

# `base` ships no editor, no manuals and no ssh, so a console-only installation
# cannot edit its own configuration, look anything up or reach another machine.
packages+=("$ARCH_OS_EDITOR" man-db man-pages openssh)

ucode="$(microcode)"
[ -n "$ucode" ] && packages+=("$ucode")
secure_boot_wanted && packages+=(sbctl)

# Before the packages, because installing the kernel builds a ram disk and the
# hook that puts a keyboard layout in it reads this file.
write_vconsole

# The longest download of the installation, and the one most likely to meet a
# mirror that stops answering halfway.
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

# The EFI partition holds the kernel and, with Secure Boot, the signed image.
# Neither is anybody's business but root's.
sed -i '/\/boot/ {s/fmask=[0-9]\+/fmask=0077/g; s/dmask=[0-9]\+/dmask=0077/g}' "${MNT}/etc/fstab"
