# Everything that makes the installed packages into this particular machine:
# clock, language, keyboard, name and swap.

simulating && return 0

# ─── Clock ───────────────────────────────────────────────────────────────────
# ln makes the link whether or not it points at anything, and a dangling
# /etc/localtime is a system that quietly runs in UTC.
if [ ! -f "${MNT}/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" ]; then
    echo "there is no time zone called ${ARCH_OS_TIMEZONE}" >&2
    exit 1
fi
arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime

# The live system keeps the same zone from here on, so the installer's log lines
# up with the journal of the machine it installed.
timedatectl set-timezone "$ARCH_OS_TIMEZONE" || true

# The hardware clock, set from a system clock that init put on network time.
arch-chroot "$MNT" hwclock --systohc

# ─── Language and keyboard ───────────────────────────────────────────────────
echo "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" >"${MNT}/etc/locale.conf"
while read -r line; do
    [ -n "$line" ] || continue
    # locale.gen already lists every locale, commented out. Matched by its
    # beginning alone, because the file pads entries with trailing spaces.
    sed -i "s|^#${line}|${line}|" "${MNT}/etc/locale.gen"
done < <(locale_gen_lines)
arch-chroot "$MNT" locale-gen

# locale-gen is happy to generate nothing, and a system whose LANG names a locale
# that was never built warns at every program and falls back to English.
if ! arch-chroot "$MNT" locale -a | grep -qxF "${ARCH_OS_LOCALE_LANG}.utf8"; then
    echo "the locale ${ARCH_OS_LOCALE_LANG}.UTF-8 was not generated" >&2
    exit 1
fi

write_vconsole

# ─── Name ────────────────────────────────────────────────────────────────────
echo "$ARCH_OS_HOSTNAME" >"${MNT}/etc/hostname"
{
    echo '# <ip>     <hostname.domain.org>  <hostname>'
    echo '127.0.0.1  localhost.localdomain  localhost'
    echo '::1        localhost.localdomain  localhost'
} >"${MNT}/etc/hosts"

# ─── Swap ────────────────────────────────────────────────────────────────────
# Compressed swap in memory: faster than a swap partition, and no SSD wear.
# https://wiki.archlinux.org/title/Zram
{
    echo '[zram0]'
    echo 'zram-size = min(ram / 2, 8192)'
    echo 'compression-algorithm = zstd'
} >"${MNT}/etc/systemd/zram-generator.conf"

# https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram
{
    echo 'vm.swappiness = 180'
    echo 'vm.watermark_boost_factor = 0'
    echo 'vm.watermark_scale_factor = 125'
    echo 'vm.page-cluster = 0'
} >"${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"
