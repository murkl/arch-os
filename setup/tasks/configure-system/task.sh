# Everything that makes the installed packages into this particular machine:
# clock, language, keyboard, name and swap.

simulating && return 0

# ─── Clock ───────────────────────────────────────────────────────────────────
arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime
arch-chroot "$MNT" hwclock --systohc

# ─── Language and keyboard ───────────────────────────────────────────────────
echo "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" >"${MNT}/etc/locale.conf"
while read -r line; do
    [ -n "$line" ] || continue
    # Uncomment the matching entry rather than appending: locale.gen already
    # lists every locale there is, commented out.
    sed -i "s|^#${line}$|${line}|" "${MNT}/etc/locale.gen"
done < <(locale_gen_lines)
arch-chroot "$MNT" locale-gen

echo "KEYMAP=${ARCH_OS_VCONSOLE_KEYMAP}" >"${MNT}/etc/vconsole.conf"
[ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=${ARCH_OS_VCONSOLE_FONT}" >>"${MNT}/etc/vconsole.conf"

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
