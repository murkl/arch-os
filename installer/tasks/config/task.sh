# What every installation is set to: clock, language, swap and the units that
# keep them running. What a choice adds is a task of its own.

# ln links whether or not the zone exists, and a dangling one is UTC in silence.
if [ ! -f "${MNT}/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" ]; then
    echo "there is no time zone called ${ARCH_OS_TIMEZONE}" >&2
    exit 1
fi
arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime
arch-chroot "$MNT" hwclock --systohc

render "$(where)/locale.conf" LOCALE="$ARCH_OS_LOCALE_LANG" >"${MNT}/etc/locale.conf"

# The chosen language and English, in UTF-8 alone. An edit: glibc's locale-gen
# reads no other file. https://wiki.archlinux.org/title/Locale
for locale in "$ARCH_OS_LOCALE_LANG" en_US; do
    sed -i -E "s/^#(${locale}(\.UTF-8)? UTF-8)/\1/" "${MNT}/etc/locale.gen"
done
arch-chroot "$MNT" locale-gen

# locale-gen is happy to generate nothing.
locales="$(arch-chroot "$MNT" locale -a)"
if ! grep -qxF "${ARCH_OS_LOCALE_LANG}.utf8" <<<"$locales"; then
    echo "the locale ${ARCH_OS_LOCALE_LANG}.UTF-8 was not generated" >&2
    exit 1
fi

# Compressed swap in memory, as a drop-in. https://wiki.archlinux.org/title/Zram
mkdir -p "${MNT}/etc/systemd/zram-generator.conf.d"
render "$(where)/zram-generator.conf" >"${MNT}/etc/systemd/zram-generator.conf.d/10-arch-os.conf"
render "$(where)/99-vm-zram-parameters.conf" >"${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"

arch-chroot "$MNT" systemctl enable fstrim.timer

# The keyring's weekly refresh, which its package switches on, asks
# archlinux.org for every key: offline it is skipped rather than failed.
mkdir -p "${MNT}/etc/systemd/system/archlinux-keyring-wkd-sync.service.d"
render "$(where)/online.conf" >"${MNT}/etc/systemd/system/archlinux-keyring-wkd-sync.service.d/online.conf"
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service

# A monthly scrub reads every block back against its checksum, so a disk going
# bad is noticed before a file is asked for. `-` is how a unit spells /.
# https://wiki.archlinux.org/title/Btrfs#Scrub
arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer

# What the kernel writes to the firmware as it crashes, moved to
# /var/lib/systemd/pstore and out of the firmware's small memory, as systemd's
# preset has it. ISO and Recovery leave it for this system to collect.
arch-chroot "$MNT" systemctl enable systemd-pstore.service

# Wherever pacstrap installed it.
if has_command irqbalance; then
    arch-chroot "$MNT" systemctl enable irqbalance.service
fi
