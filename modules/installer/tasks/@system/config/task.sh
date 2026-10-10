# What every installation is set to: clock, language, name, swap and the units
# that keep them running. What only some get is a task of its own.

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

# /etc/hosts stays as shipped: nss-myhostname answers for this name.
# https://wiki.archlinux.org/title/Network_configuration#Local_hostname_resolution
echo "$ARCH_OS_HOSTNAME" >"${MNT}/etc/hostname"

# Compressed swap in memory, as a drop-in. https://wiki.archlinux.org/title/Zram
mkdir -p "${MNT}/etc/systemd/zram-generator.conf.d"
render "$(where)/zram-generator.conf" >"${MNT}/etc/systemd/zram-generator.conf.d/10-arch-os.conf"
render "$(where)/99-vm-zram-parameters.conf" >"${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"

arch-chroot "$MNT" systemctl enable NetworkManager

# A key of one [section] of an iwd profile.
iwd_setting() {
    awk -v section="[$2]" -v key="$3" '
        /^\[/ { inside = ($0 == section); next }
        inside && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
    ' "$1"
}

# Every wireless network the live system joined, so the first boot is online.
# iwd names a profile after the SSID, or "=" and its hex; nmcli writes the
# keyfile without a running daemon. A network with 802.1X is joined again by
# hand. https://man.archlinux.org/man/iwd.network.5
for profile in /var/lib/iwd/*.psk /var/lib/iwd/*.open; do
    [ -f "$profile" ] || continue
    name="$(basename "$profile")"
    name="${name%.*}"
    ssid="$name"
    if [[ $name == =* ]]; then
        hex="${name#=}" escaped=""
        while [ -n "$hex" ]; do
            escaped+="\\x${hex:0:2}"
            hex="${hex:2}"
        done
        ssid="$(printf '%b' "$escaped")"
    fi
    args=(type wifi con-name "$ssid" ssid "$ssid")
    if [ "$(iwd_setting "$profile" Settings Hidden)" = "true" ]; then
        args+=(wifi.hidden yes)
    fi
    # wpa-psk is WPA2 and WPA3 Personal alike; the processed key stands in
    # where iwd kept no passphrase.
    if [[ $profile == *.psk ]]; then
        secret="$(iwd_setting "$profile" Security Passphrase)"
        [ -n "$secret" ] || secret="$(iwd_setting "$profile" Security PreSharedKey)"
        args+=(wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$secret")
    fi
    keyfile="${MNT}/etc/NetworkManager/system-connections/${name}.nmconnection"
    (umask 077 && arch-chroot "$MNT" nmcli --offline connection add "${args[@]}" >"$keyfile")
    echo "carried over the wireless network ${ssid}"
done
arch-chroot "$MNT" systemctl enable fstrim.timer
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service

# A monthly scrub reads every block back against its checksum, so a disk going
# bad is noticed before a file is asked for. `-` is how a unit spells /.
# https://wiki.archlinux.org/title/Btrfs#Scrub
arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer
