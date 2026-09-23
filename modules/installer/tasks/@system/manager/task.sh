# A menu for updating, cleaning up and repairing the system after this installer
# is gone. https://github.com/murkl/arch-os-manager

chroot_pacman_install pacman-contrib
chroot_aur_install arch-os-manager

# The binaries the manager draws itself with, fetched now rather than on the
# machine. GUM is unset because it would point the manager at whatever copy this
# environment holds, and setsid because --init asks its question on /dev/tty
# rather than on stdin - with no controlling terminal it answers itself.
#
# The status is read into a variable rather than with `$?` inside an `if !`,
# where bash reports the negation and every outcome reads as 0. --init ends on 2
# rather than 0 when it worked.
#
# Nothing here may fail the installation: this is a head start, and the manager
# fetches the same binaries itself the first time it is opened.
status=0
as_user 'unset GUM; timeout 300 setsid --wait /usr/bin/arch-os --init' </dev/null || status=$?
case "$status" in
0 | 2) ;;
124) echo "the manager's binaries did not download in time; it will fetch them on first use" >&2 ;;
*) echo "the manager's binaries could not be downloaded (${status}); it will fetch them on first use" >&2 ;;
esac
