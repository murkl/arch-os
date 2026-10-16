# A menu for updating, cleaning up and repairing the system afterwards.
# https://github.com/murkl/arch-os-manager
chroot_pacman_install pacman-contrib
chroot_aur_install arch-os-manager

# Its app menu entry and update notification now rather than at its first
# start, which puts them in place all the same; so nothing here fails the
# installation.
if ! as_user 'system-manager init' </dev/null; then
    echo "the manager's menu entry waits for its first start" >&2
fi
