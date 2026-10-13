# A menu for updating, cleaning up and repairing the system afterwards.
# https://github.com/murkl/arch-os-manager
chroot_pacman_install pacman-contrib
chroot_aur_install arch-os-manager

# Its binaries now rather than on first use, which fetches them all the same,
# so nothing here fails the installation. --init ends on 2 when it worked.
status=0
as_user 'unset GUM; timeout 300 setsid --wait /usr/bin/arch-os --init' </dev/null || status=$?
case "$status" in
0 | 2) ;;
124) echo "the manager's binaries did not download in time; it will fetch them on first use" >&2 ;;
*) echo "the manager's first start stopped with ${status}; it sets itself up again on first use" >&2 ;;
esac
