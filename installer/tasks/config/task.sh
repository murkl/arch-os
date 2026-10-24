# ln also links a missing zone, and a dangling link silently means UTC.
if [ ! -f "${MNT}/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" ]; then
    echo "unknown time zone ${ARCH_OS_TIMEZONE}" >&2
    exit 1
fi
arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime
arch-chroot "$MNT" hwclock --systohc

render "$(where)/locale.conf" LOCALE="$ARCH_OS_LOCALE_LANG" >"${MNT}/etc/locale.conf"

# The chosen locale and en_US, UTF-8 only. Edited in place, since locale-gen
# reads no other file. https://wiki.archlinux.org/title/Locale
for locale in "$ARCH_OS_LOCALE_LANG" en_US; do
    sed -i -E "s/^#(${locale}(\.UTF-8)? UTF-8)/\1/" "${MNT}/etc/locale.gen"
done
arch-chroot "$MNT" locale-gen

# locale-gen also succeeds when it generates nothing.
locales="$(arch-chroot "$MNT" locale -a)"
if ! grep -qxF "${ARCH_OS_LOCALE_LANG}.utf8" <<<"$locales"; then
    echo "the locale ${ARCH_OS_LOCALE_LANG}.UTF-8 was not generated" >&2
    exit 1
fi

# https://wiki.archlinux.org/title/Zram
mkdir -p "${MNT}/etc/systemd/zram-generator.conf.d"
render "$(where)/zram-generator.conf" >"${MNT}/etc/systemd/zram-generator.conf.d/10-arch-os.conf"
render "$(where)/99-vm-zram-parameters.conf" >"${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"

arch-chroot "$MNT" systemctl enable fstrim.timer

# archlinux-keyring enables a weekly refresh that asks archlinux.org for every
# key. Offline it is skipped instead of failed.
mkdir -p "${MNT}/etc/systemd/system/archlinux-keyring-wkd-sync.service.d"
render "$(where)/online.conf" >"${MNT}/etc/systemd/system/archlinux-keyring-wkd-sync.service.d/online.conf"
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service

# A monthly scrub finds a failing disk before a file read does. `-` is / escaped
# as a unit name.
# https://wiki.archlinux.org/title/Btrfs#Scrub
arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer

# Moves crash logs from the firmware's small pstore to /var/lib/systemd/pstore,
# as systemd's preset does. The ISO and the Recovery leave them for this system.
arch-chroot "$MNT" systemctl enable systemd-pstore.service
