# None of these change what is installed. They change how it behaves in the
# small ways that are noticed every day.

simulating && return 0

# Stars while typing a sudo password, so a terminal does not look frozen.
sudoers_rule 20-pwfeedback 'Defaults pwfeedback'

# Parallel downloads and colour, which pacman ships switched off. pacman has
# no drop-in directory - every setting and every repository has to be a
# section of this one file - so this is an edit, and one of the few places a
# .pacnew is still possible.
sed -i 's/^#ParallelDownloads/ParallelDownloads/' "${MNT}/etc/pacman.conf"
sed -i 's/^#Color/Color\nILoveCandy/' "${MNT}/etc/pacman.conf"

# The hardware watchdogs, which nothing here uses and which delay shutdown.
mkdir -p "${MNT}/etc/modprobe.d"
{
    echo 'blacklist sp5100_tco'
    echo 'blacklist iTCO_wdt'
} >"${MNT}/etc/modprobe.d/blacklist-watchdog.conf"

# Debug packages nobody asked for, built alongside every AUR package. As a
# drop-in: /etc/makepkg.conf belongs to pacman and is rewritten often enough that
# editing it would leave a .pacnew to merge after most pacman updates.
mkdir -p "${MNT}/etc/makepkg.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    echo 'OPTIONS+=(!debug)'
} >"${MNT}/etc/makepkg.conf.d/arch-os.conf"
