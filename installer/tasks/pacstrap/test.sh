[ -x "${MNT}/usr/bin/pacman" ]
[ -f "${MNT}/boot/vmlinuz-${KERNEL}" ]
grep -qx "KEYMAP=$(vconsole_keymap)" "${MNT}/etc/vconsole.conf"

# A font the system lacks leaves the console on the kernel's at every boot, and
# says so nowhere.
font="$(sed -n 's/^FONT=//p' "${MNT}/etc/vconsole.conf")"
[ -z "$font" ] || compgen -G "${MNT}/usr/share/kbd/consolefonts/${font}.psf*" >/dev/null

# The table read by the tool that reads it at boot: one missing either is a
# machine that comes up in an emergency shell.
findmnt --fstab --tab-file "${MNT}/etc/fstab" / >/dev/null

# The sed matches what genfstab writes today, and says nothing the day it changes.
boot_options="$(findmnt --fstab --tab-file "${MNT}/etc/fstab" -no OPTIONS /boot)"
grep -qE '(^|,)fmask=0077(,|$)' <<<"$boot_options"
grep -qE '(^|,)dmask=0077(,|$)' <<<"$boot_options"

# Checked at every boot, which needs a pass and the tool for its file system.
[ "$(findmnt --fstab --tab-file "${MNT}/etc/fstab" -no PASSNO /boot)" -gt 0 ]
[ -x "${MNT}/usr/bin/fsck.fat" ]
