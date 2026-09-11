# A menu for updating, cleaning up and repairing the system after this installer
# is gone.

simulating && return 0

chroot_pacman_install git base-devel pacman-contrib
chroot_aur_install arch-os-manager

# GUM is unset because the manager fetches its own copy on first run, and the
# variable would point it at whatever this environment holds. --init downloads
# with no timeout of its own, so a stalled connection would hang the install
# rather than fail it. It also exits 2 on success, which the error trap would
# otherwise read as a failure.
if ! as_user 'unset GUM; timeout 300 /usr/bin/arch-os --init'; then
    status=$?
    [ "$status" -eq 2 ] || exit "$status"
fi
