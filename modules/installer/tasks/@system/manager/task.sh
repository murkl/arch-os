# A menu for updating, cleaning up and repairing the system after this installer
# is gone.

simulating && return 0

chroot_pacman_install git base-devel pacman-contrib
chroot_aur_install arch-os-manager

# The binaries the manager draws itself with, fetched now rather than on the
# machine. GUM is unset because it would point the manager at whatever copy this
# environment holds; stdin is closed because anything --init asks would
# otherwise wait for an answer nobody is there to give, which is what made this
# sit out the whole timeout below on every installation. --init brings no
# timeout of its own, so a stalled download gets one here.
#
# The status is read into a variable rather than with `$?` inside an `if !`,
# where bash reports the negation and every outcome reads as 0 - which is how a
# run that was killed after five minutes still reported success. --init ends on
# 2 rather than 0 when it worked.
#
# Nothing here may fail the installation: this is a head start, and the manager
# fetches the same binaries itself the first time it is opened. What became of
# it is said in the log instead.
status=0
as_user 'unset GUM; timeout 300 /usr/bin/arch-os --init' </dev/null || status=$?
case "$status" in
0 | 2) ;;
124) echo "the manager's binaries did not download in time; it will fetch them on first use" >&2 ;;
*) echo "the manager's binaries could not be downloaded (${status}); it will fetch them on first use" >&2 ;;
esac
