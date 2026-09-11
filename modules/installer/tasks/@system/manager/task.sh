# A menu for updating, cleaning up and repairing the system after this installer
# is gone.

simulating && return 0

chroot_pacman_install git base-devel pacman-contrib
chroot_aur_install arch-os-manager

# The binaries the manager draws itself with, fetched now rather than on the
# machine. GUM is unset because it would point the manager at whatever copy this
# environment holds.
#
# setsid, because --init asks a question when it finds something it does not
# like, and the prompt it asks with opens /dev/tty rather than reading stdin -
# closing stdin does not reach it. With no controlling terminal there is no
# /dev/tty to open, so the question answers itself and the run carries on.
# Without it this sat out the whole timeout below on every single installation.
#
# The status is read into a variable rather than with `$?` inside an `if !`,
# where bash reports the negation and every outcome reads as 0 - which is how a
# run that was killed after five minutes still reported success. --init ends on
# 2 rather than 0 when it worked, and the timeout is the last line of defence.
#
# Nothing here may fail the installation: this is a head start, and the manager
# fetches the same binaries itself the first time it is opened. What became of
# it is said in the log instead.
status=0
as_user 'unset GUM; timeout 300 setsid --wait /usr/bin/arch-os --init' </dev/null || status=$?
case "$status" in
0 | 2) ;;
124) echo "the manager's binaries did not download in time; it will fetch them on first use" >&2 ;;
*) echo "the manager's binaries could not be downloaded (${status}); it will fetch them on first use" >&2 ;;
esac
