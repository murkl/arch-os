# A menu for updating, cleaning up and repairing the system afterwards.
# https://github.com/murkl/arch-os-manager
chroot_pacman_install pacman-contrib
chroot_aur_install arch-os-manager

# Its binaries fetched now rather than on first use. GUM unset so it ignores
# this environment's copy, setsid because --init asks on /dev/tty. --init ends
# on 2 when it worked, and nothing here may fail the installation: the manager
# fetches the same itself when it is first opened.
status=0
as_user 'unset GUM; timeout 300 setsid --wait /usr/bin/arch-os --init' </dev/null || status=$?
case "$status" in
0 | 2) ;;
124) echo "the manager's binaries did not download in time; it will fetch them on first use" >&2 ;;
*) echo "the manager's first start stopped with ${status}; it sets itself up again on first use" >&2 ;;
esac
