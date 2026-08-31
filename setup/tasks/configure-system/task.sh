# Everything that makes the installed packages into this particular machine:
# clock, language, keyboard, name and swap.

simulating && return 0

# ─── Clock ───────────────────────────────────────────────────────────────────
# A symbolic link is made whether or not it points at anything, and a dangling
# /etc/localtime is a system that quietly runs in UTC — so the zone is looked
# for before it is linked to.
if [ ! -f "${MNT}/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" ]; then
    echo "there is no time zone called ${ARCH_OS_TIMEZONE}" >&2
    exit 1
fi
arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime

# The live system keeps the same zone from here on. Nothing on the new system
# depends on it — the hardware clock is written in UTC either way — but the
# installer's own log is stamped with it, and a log that reads in a different
# time zone than the journal of the machine it installed is a log nobody can
# line up with anything.
timedatectl set-timezone "$ARCH_OS_TIMEZONE" || true

# The hardware clock, set from a system clock that init put on network time.
arch-chroot "$MNT" hwclock --systohc

# ─── Language and keyboard ───────────────────────────────────────────────────
echo "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" >"${MNT}/etc/locale.conf"
while read -r line; do
    [ -n "$line" ] || continue
    # Uncomment the matching entry rather than appending: locale.gen already
    # lists every locale there is, commented out. Matched by its beginning
    # alone, because the file pads its entries with trailing spaces and an
    # anchored pattern would find none of them.
    sed -i "s|^#${line}|${line}|" "${MNT}/etc/locale.gen"
done < <(locale_gen_lines)
arch-chroot "$MNT" locale-gen

# locale-gen is happy to generate nothing at all, and a system whose LANG names
# a locale that was never built answers every program with a warning and falls
# back to English.
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
# Compressed swap in memory rather than on disk: faster than a swap partition,
# and it does not wear out an SSD.
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
