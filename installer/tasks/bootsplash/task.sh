# https://wiki.archlinux.org/title/Plymouth
chroot_pacman_install plymouth

# After base and systemd in the hooks of the bootloader task.
run mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/20-plymouth.conf" | write_file "${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

run mkdir -p "${MNT}/usr/local/lib/arch-os"
render "$(where)/plymouthd-shutdown" | write_file "${MNT}/usr/local/lib/arch-os/plymouthd-shutdown"
run chmod 755 "${MNT}/usr/local/lib/arch-os/plymouthd-shutdown"

# Each shutdown splash starts through it, with the package's arguments, so
# each unit keeps its mode.
for unit in "${MNT}"/usr/lib/systemd/system/plymouth-*.service; do
    [ -f "$unit" ] || continue # no match, caught by the test's unit list
    args="$(sed -n 's|^ExecStart=/usr/bin/plymouthd \(--mode=[a-z]* .*\)|\1|p' "$unit")"
    case "$args" in "" | --mode=boot*) continue ;; esac
    unit="$(basename "$unit")"
    run mkdir -p "${MNT}/etc/systemd/system/${unit}.d"
    render "$(where)/shutdown.conf" ARGS="$args" | write_file "${MNT}/etc/systemd/system/${unit}.d/10-arch-os.conf"
done

# Rebuilt even without the theme, so no image lacks the hook, and the failure
# comes last. In a subshell, since an unreachable AUR ends the build's shell.
# Not `plymouth-set-default-theme -R`, which always exits 0.
failed=0
(chroot_aur_install plymouth-theme-arch-os) || failed=$?
if [ "$failed" -eq 0 ]; then
    run arch-chroot "$MNT" plymouth-set-default-theme arch-os
fi
run arch-chroot "$MNT" mkinitcpio -P
[ "$failed" -eq 0 ] || exit "$failed"
