# Make the live system ready to install from.
#
# Nothing here touches the target disk. It undoes whatever a previous attempt
# left mounted, waits for the live image to finish choosing mirrors, and brings
# the keyring up to date — the three things that otherwise fail the next stage
# for reasons that have nothing to do with it.

simulating && return 0

# The live image ranks mirrors in the background at boot, and the list it
# produces is copied into the new system. Starting before it is done means
# installing from whatever was there first.
echo "waiting for reflector"
while timeout 180 tail --pid="$(pgrep reflector)" -f /dev/null &>/dev/null; do sleep 1; done
if pgrep reflector &>/dev/null; then
    echo "reflector is still running after 180 seconds" >&2
    exit 1
fi

timedatectl set-ntp true

# Some old routers drop connections that use explicit congestion notification,
# which shows up as an install that stalls partway through a download.
[ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0

# Anything a previous attempt left behind, cleared. All of it is allowed to fail:
# on a first run there is nothing there to close.
swapoff -a || true
umount -R "${MNT}/recovery" || true
if [[ "$(umount -f -A -R "$MNT" 2>&1)" == *"target is busy"* ]]; then
    fuser -km "$MNT" || true
    umount -f -A -R "$MNT" || true
fi
cryptsetup close cryptroot || true
cryptsetup close cryptrecovery || true
vgchange -an || true
rm -f /var/lib/pacman/db.lck

# A stale keyring is the single most common reason a fresh install refuses to
# verify a package it just downloaded.
pacman -Sy --noconfirm archlinux-keyring
