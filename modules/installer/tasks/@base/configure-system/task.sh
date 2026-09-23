# What makes the installed packages into this particular machine: clock,
# language, keyboard, name, swap, and the units that keep them running.
#
# All of it unconditional. What only some machines get is a task of its own,
# with the answer that decides it written into its yaml.

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
render "$(where)/locale.conf" LOCALE="$ARCH_OS_LOCALE_LANG" >"${MNT}/etc/locale.conf"

# Every line of /etc/locale.gen belonging to the chosen language, plus English
# as a fallback. Matched by its beginning alone, because the file pads entries
# with trailing spaces. An edit rather than a drop-in: the file belongs to glibc
# and locale-gen reads no other.
# https://wiki.archlinux.org/title/Locale
{
    sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "^${ARCH_OS_LOCALE_LANG}" || true
    echo 'en_US.UTF-8 UTF-8'
} | while read -r line; do
    [ -n "$line" ] || continue
    sed -i "s|^#${line}|${line}|" "${MNT}/etc/locale.gen"
done
arch-chroot "$MNT" locale-gen

# locale-gen is happy to generate nothing, and a system whose LANG names a
# locale that was never built warns at every program.
if ! arch-chroot "$MNT" locale -a | grep -qxF "${ARCH_OS_LOCALE_LANG}.utf8"; then
    echo "the locale ${ARCH_OS_LOCALE_LANG}.UTF-8 was not generated" >&2
    exit 1
fi

write_vconsole

# ----------------------------------------------------------------------------

# Name. /etc/hosts is left as the filesystem package ships it: localhost is in
# there already, and nss-myhostname answers for the name set here.
# https://wiki.archlinux.org/title/Network_configuration#Local_hostname_resolution
echo "$ARCH_OS_HOSTNAME" >"${MNT}/etc/hostname"

# ----------------------------------------------------------------------------

# The editor everything that asks for one gets. Here rather than in a shell's
# own configuration, because sudoedit, git and systemctl edit are not shells:
# they read $EDITOR, and without one they fall back on vi, which `base` does not
# ship. pam_env reads this one file and no directory beside it, so it is an edit.
# https://wiki.archlinux.org/title/Environment_variables
editor="$ARCH_OS_EDITOR"
[ "$editor" = "neovim" ] && editor="nvim" # the package is neovim, the command nvim
render "$(where)/environment" EDITOR="$editor" >>"${MNT}/etc/environment"

# ----------------------------------------------------------------------------

# Compressed swap in memory: faster than a swap partition, and no SSD wear.
# As a drop-in, which leaves /etc/systemd/zram-generator.conf to whoever owns
# the machine. https://wiki.archlinux.org/title/Zram
mkdir -p "${MNT}/etc/systemd/zram-generator.conf.d"
render "$(where)/zram-generator.conf" >"${MNT}/etc/systemd/zram-generator.conf.d/10-arch-os.conf"

# https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram
render "$(where)/99-vm-zram-parameters.conf" >"${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"

# ----------------------------------------------------------------------------

# The services a working system runs, switched on so the first boot comes up
# with a network, a clock and the swap set up above.
arch-chroot "$MNT" systemctl enable NetworkManager
arch-chroot "$MNT" systemctl enable fstrim.timer                     # keeps an SSD fast
arch-chroot "$MNT" systemctl enable systemd-zram-setup@zram0.service # the swap set up above
arch-chroot "$MNT" systemctl enable systemd-oomd.service             # kills a runaway before the machine locks up
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service
