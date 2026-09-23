# The packages the system is made of, and the file system table.
# https://wiki.archlinux.org/title/Installation_guide#Install_essential_packages
#
# What is here and what is not: docs/REFERENCE.md

# sudo is named outright: it comes with base-devel, which only an installation
# that builds from the AUR needs, and the wheel rule is written either way.
packages=("$ARCH_OS_KERNEL" base sudo zram-generator networkmanager)

# Firmware is for hardware, and a guest has none. The exception is a card handed
# through to one, and the graphics answer is where that is said.
needs_firmware() {
    [ "$(systemd-detect-virt || true)" = "none" ] && return 0
    case "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" in
    nvidia | amd | ati | intel_i915) return 0 ;;
    esac
    return 1
}

if needs_firmware; then
    packages+=(linux-firmware wireless-regdb)
else
    echo "a virtual machine with no card of its own: leaving out linux-firmware"
fi

# `base` ships no editor, no manuals and no ssh, so a console-only installation
# cannot edit its own configuration, look anything up or reach another machine.
packages+=("$ARCH_OS_EDITOR" man-db man-pages openssh)

[ "$ARCH_OS_MICROCODE" != "none" ] && packages+=("$ARCH_OS_MICROCODE")
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs)
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BTRFS_SNAPPER_ENABLED" = "true" ] && packages+=(snapper)
secure_boot_wanted && packages+=(sbctl)

# grub-install writes the firmware boot entry through efibootmgr; bootctl talks
# to efivarfs itself and needs neither. grub-btrfsd watches the snapshot
# directory with inotify.
if [ "$ARCH_OS_BOOTLOADER" = "grub" ]; then
    packages+=(grub efibootmgr)
    [ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && packages+=(grub-btrfs inotify-tools)
    # Finds the other system so GRUB can offer it.
    [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && packages+=(os-prober)
fi

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
