# Everything that makes the installed packages into this particular machine:
# clock, language, keyboard, name, swap - and the units that keep them running.
#
# All of it unconditional. What only some machines get is a task of its own with
# the answer that decides it written into its yaml, so a run lists the step it
# is actually taking - see the congestion notification and the scrub beside it.

simulating && return 0

# Clock. ln makes the link whether or not it points at anything, so a
# dangling /etc/localtime would be a system that quietly runs in UTC.
if [ ! -f "${MNT}/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" ]; then
    echo "there is no time zone called ${ARCH_OS_TIMEZONE}" >&2
    exit 1
fi
arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime

# The live system keeps the same zone from here on, so the installer's log
# lines up with the journal of the machine it installed.
timedatectl set-timezone "$ARCH_OS_TIMEZONE" || true

# The hardware clock, set from a system clock that init put on network time.
arch-chroot "$MNT" hwclock --systohc

# ----------------------------------------------------------------------------

# Language and keyboard.
echo "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" >"${MNT}/etc/locale.conf"

# Every line of /etc/locale.gen belonging to the chosen language, plus English
# as a fallback. locale.gen already lists every locale, commented out; each is
# matched by its beginning alone, because the file pads entries with trailing
# spaces.
#
# The file belongs to glibc and locale-gen reads no other, so this is an edit
# rather than a drop-in, and one of the few places a .pacnew is still possible.
{
    sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "^${ARCH_OS_LOCALE_LANG}" || true
    echo 'en_US.UTF-8 UTF-8'
} | while read -r line; do
    [ -n "$line" ] || continue
    sed -i "s|^#${line}|${line}|" "${MNT}/etc/locale.gen"
done
arch-chroot "$MNT" locale-gen

# locale-gen is happy to generate nothing, and a system whose LANG names a
# locale that was never built warns at every program and falls back to English.
if ! arch-chroot "$MNT" locale -a | grep -qxF "${ARCH_OS_LOCALE_LANG}.utf8"; then
    echo "the locale ${ARCH_OS_LOCALE_LANG}.UTF-8 was not generated" >&2
    exit 1
fi

write_vconsole

# ----------------------------------------------------------------------------

# Name.
echo "$ARCH_OS_HOSTNAME" >"${MNT}/etc/hostname"
{
    echo '# <ip>     <hostname.domain.org>  <hostname>'
    echo '127.0.0.1  localhost.localdomain  localhost'
    echo '::1        localhost.localdomain  localhost'
} >"${MNT}/etc/hosts"

# ----------------------------------------------------------------------------

# The editor everything that asks for one gets. pam_env reads this file at every
# login there is - a text console, ssh, the desktop - and systemd hands the same
# file to the user manager as 99-environment.conf, so a graphical program sees
# it too.
#
# Here rather than in each shell's own configuration: sudoedit, git and
# systemctl edit are not shells, they read $EDITOR, and what they fall back on
# without one is vi, which `base` does not ship. The shell enhancement is also a
# thing somebody can turn off, and an editor is not.
#
# An edit rather than a drop-in, because pam_env reads this one file and no
# directory beside it. It belongs to the filesystem package, which ships it
# holding nothing but comments.
{
    echo '# Written by the Arch OS Installer.'
    echo 'EDITOR=nano'
    echo 'VISUAL=nano'
} >>"${MNT}/etc/environment"

# ----------------------------------------------------------------------------

# Swap. Compressed swap in memory: faster than a swap partition, and no SSD
# wear. https://wiki.archlinux.org/title/Zram
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

# ----------------------------------------------------------------------------

# The services a working system runs, switched on so the first boot comes up
# with a network, a clock and the swap set up above.
arch-chroot "$MNT" systemctl enable NetworkManager
arch-chroot "$MNT" systemctl enable fstrim.timer                     # keeps an SSD fast
arch-chroot "$MNT" systemctl enable systemd-zram-setup@zram0.service # the swap set up above
arch-chroot "$MNT" systemctl enable systemd-oomd.service             # kills a runaway before the machine locks up
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service
