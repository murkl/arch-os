# What every installation is set to: clock, language, name, swap and the units
# that keep them running. What only some get is a task of its own.

# ln links whether or not the zone exists, and a dangling one is UTC in silence.
if [ ! -f "${MNT}/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" ]; then
    echo "there is no time zone called ${ARCH_OS_TIMEZONE}" >&2
    exit 1
fi
arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime

# The live system follows, so the installer's log lines up with the journal.
timedatectl set-timezone "$ARCH_OS_TIMEZONE" || true
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

# /etc/hosts stays as shipped: nss-myhostname answers for this name.
# https://wiki.archlinux.org/title/Network_configuration#Local_hostname_resolution
echo "$ARCH_OS_HOSTNAME" >"${MNT}/etc/hostname"

# Compressed swap in memory, as a drop-in. https://wiki.archlinux.org/title/Zram
mkdir -p "${MNT}/etc/systemd/zram-generator.conf.d"
render "$(where)/zram-generator.conf" >"${MNT}/etc/systemd/zram-generator.conf.d/10-arch-os.conf"
render "$(where)/99-vm-zram-parameters.conf" >"${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"

arch-chroot "$MNT" systemctl enable NetworkManager
arch-chroot "$MNT" systemctl enable fstrim.timer
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service

# A monthly scrub reads every block back against its checksum, so a disk going
# bad is noticed before a file is asked for. `-` is how a unit spells /.
# https://wiki.archlinux.org/title/Btrfs#Scrub
arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer
