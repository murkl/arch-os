# Make the live system ready to install from. Nothing here touches the target
# disk: it undoes what a previous attempt left mounted, waits for the mirror
# ranking to finish and brings the keyring up to date.

simulating && return 0

# The live image ranks mirrors at boot and that list is copied into the new
# system. Starting early means installing from whatever was there first.
echo "waiting for reflector"
if ! timeout 180 bash -c 'while pgrep -x reflector >/dev/null; do sleep 1; done'; then
    echo "reflector is still running after 180 seconds" >&2
    exit 1
fi

timedatectl set-ntp true

# Some old routers drop connections that use it, which shows up as an install
# stalling partway through a download.
[ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0

# What a previous attempt left behind. All of it may fail — on a first run there
# is nothing to close.
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

# A stale keyring is the commonest reason a fresh install refuses to verify a
# package it just downloaded.
pacman -Sy --noconfirm archlinux-keyring
