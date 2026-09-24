# The images the firmware starts: the initial ram disk, or - where the boot chain
# is signed - the unified kernel image that replaces it.
#
# Before the boot loader, because the loader points at what this leaves behind,
# and after the base system, because building a ram disk is mkinitcpio running
# inside the installed one. Why these hooks and in this order: docs/REFERENCE.md
# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks

data="$(where)"

encrypt_hook=""
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && encrypt_hook=" sd-encrypt"

hooks="base systemd keyboard autodetect microcode modconf kms sd-vconsole block${encrypt_hook} filesystems"

# As a drop-in: mkinitcpio reads its own file first and every drop-in after it
# in name order, so the boot splash (20-) and the graphics driver (30-) build on
# this one.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "${data}/10-arch-os.conf" HOOKS="$hooks" >"${MNT}/etc/mkinitcpio.conf.d/10-arch-os.conf"

# A unified kernel image packs kernel, ram disk and command line into one EFI
# binary that is signed as a whole; without Secure Boot the same two images are
# plain ram disks the boot loader points at. The same word picks the preset
# written below.
key=image
if secure_boot_wanted; then
    key=uki
    mkdir -p "${MNT}/boot/EFI/Linux" "${MNT}/etc/kernel"

    # The command line moves into the image, so it has to exist first: without
    # this file mkinitcpio falls back to /proc/cmdline, which inside the chroot
    # is the live image's.
    kernel_args >"${MNT}/etc/kernel/cmdline"

    # The keys the chain is signed with, made here rather than with the signing
    # at the end: before anything takes a snapshot of this system. A snapshot
    # without them comes back unable to sign what it rebuilds, and with Secure
    # Boot on, nothing rebuilt would start again. From here on sbctl's own hook
    # signs every image mkinitcpio writes. Never fatal, like the signing.
    arch-chroot "$MNT" sbctl create-keys || echo "Secure Boot: creating the keys failed, nothing will be signed" >&2
fi

# Both names come out of boot_images, so what is built and what is read back
# afterwards cannot come apart.
mapfile -t images < <(boot_images)

# Written whole rather than patched, and on both paths rather than only the
# signed one: mkinitcpio writes its own template only where there is no preset,
# and that template builds the default image alone. Left to it, the fallback -
# the image that boots a machine its autodetect has stopped being true for -
# would quietly not exist while the boot entry pointing at it stayed. The signed
# one names its command line outright: mkinitcpio's last resort is /proc/cmdline.
render "${data}/${key}.preset" KERNEL="$KERNEL" DEFAULT="${images[0]}" FALLBACK="${images[1]}" \
    >"${MNT}/etc/mkinitcpio.d/${KERNEL}.preset"

arch-chroot "$MNT" mkinitcpio -P

# Installing the kernel already built a plain ram disk from the preset the
# package shipped. With the preset above it is never written again, and an
# initramfs nothing updates is what the unified image does away with.
if secure_boot_wanted; then
    rm -f "${MNT}/boot/initramfs-${KERNEL}.img" "${MNT}/boot/initramfs-${KERNEL}-fallback.img"
fi
