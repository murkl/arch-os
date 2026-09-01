# None of these change what is installed. They change how it behaves in the small
# ways that are noticed every day.

simulating && return 0

# Stars while typing a sudo password, so a terminal does not look frozen.
printf '\n## Show feedback while a sudo password is typed\nDefaults pwfeedback\n' >>"${MNT}/etc/sudoers"

# Parallel downloads and colour, which pacman ships switched off.
sed -i 's/^#ParallelDownloads/ParallelDownloads/' "${MNT}/etc/pacman.conf"
sed -i 's/^#Color/Color\nILoveCandy/' "${MNT}/etc/pacman.conf"

# The hardware watchdogs, which nothing here uses and which delay shutdown.
mkdir -p "${MNT}/etc/modprobe.d"
{
    echo 'blacklist sp5100_tco'
    echo 'blacklist iTCO_wdt'
} >"${MNT}/etc/modprobe.d/blacklist-watchdog.conf"

# Debug packages nobody asked for, built alongside every AUR package.
sed -i '/OPTIONS=.*!debug/!s/\(OPTIONS=.*\)debug/\1!debug/' "${MNT}/etc/makepkg.conf"
