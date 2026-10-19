[ -x "${MNT}/usr/bin/pacman" ]
[ -f "${MNT}/boot/vmlinuz-${KERNEL}" ]
grep -qx "KEYMAP=$(vconsole_keymap)" "${MNT}/etc/vconsole.conf"

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
