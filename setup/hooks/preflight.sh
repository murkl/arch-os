# Can this machine be installed onto at all?
#
# Everything here is read-only and everything here is a wall. It runs before the
# first question, because being told the firmware is wrong is worth very little
# after twenty answers — and because none of it can be fixed from inside this
# program.
#
# What is written to stderr is what the user reads, so each message says what is
# wrong and what to do about it, in that order, and nothing else.

# DEBUG=true takes every wall down and simulates the installation instead of
# running it — see scripts/lib.sh. None of what follows is true on the machine a
# run is usually tried out on, so none of it is asked.
[ "${DEBUG:-false}" = "true" ] && return 0

if [ "$(id -u)" -ne 0 ]; then
    echo "The installer has to run as root. Log in as root and start it again." >&2
    exit 1
fi

if [ ! -d /sys/firmware/efi ]; then
    echo "This machine booted in BIOS mode, which Arch OS does not install to. Set the boot mode to UEFI in the firmware settings and start again." >&2
    exit 1
fi

if ! bootctl status 2>/dev/null | grep -q "Secure Boot: disabled"; then
    echo "Secure Boot is switched on. Turn it off in the firmware settings and start again — the installer can set it up again for you afterwards." >&2
    exit 1
fi

if [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ]; then
    echo "The installer only runs from the Arch Linux live image. Boot that image and start it from there." >&2
    exit 1
fi

# The network is checked rather than assumed: everything from here on downloads
# something, and a link that is merely slow to come up after boot is common
# enough to be worth waiting for rather than failing on.
online=false
for i in 1 2 3 4 5; do
    [ "$i" -gt 1 ] && echo "retry ${i}/5: waiting for the network" && sleep 5
    if curl -Lsf --connect-timeout 5 --max-time 15 https://archlinux.org >/dev/null 2>&1; then
        online=true
        break
    fi
done
if [ "$online" != "true" ]; then
    echo "No internet connection. Connect this machine to the network — use iwctl for wireless — and start the installer again." >&2
    exit 1
fi

echo "preflight ok: UEFI, Secure Boot off, live image, network up"
