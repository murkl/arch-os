# Arch OS Manager: a menu for updating, cleaning up and repairing the system
# after this installer is gone.

simulating && return 0

chroot_pacman_install git base-devel pacman-contrib
chroot_aur_install arch-os-manager

# GUM is unset because the manager downloads its own copy on first run, and the
# variable would point it at whatever this environment happens to hold.
#
# --init fetches gum and a kitty binary over the network with no timeout of
# its own, so a stalled connection would otherwise hang the install rather
# than fail it; timeout bounds that. It also exits 2 on a successful init
# instead of 0, which this script's own error trap would otherwise read as a
# failure — so that one exit code is let through rather than trapped.
if ! as_user 'unset GUM; timeout 300 /usr/bin/arch-os --init'; then
    status=$?
    [ "$status" -eq 2 ] || exit "$status"
fi
