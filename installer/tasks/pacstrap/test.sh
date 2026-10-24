[ -x "${MNT}/usr/bin/pacman" ]
[ -f "${MNT}/boot/vmlinuz-${KERNEL}" ]
grep -qx "KEYMAP=$(vconsole_keymap)" "${MNT}/etc/vconsole.conf"

# A missing font silently leaves the console on the kernel's.
font="$(sed -n 's/^FONT=//p' "${MNT}/etc/vconsole.conf")"
[ -z "$font" ] || compgen -G "${MNT}/usr/share/kbd/consolefonts/${font}.psf*" >/dev/null

# Parsed as systemd reads it at boot. A broken entry boots into the emergency
# shell.
findmnt --fstab --tab-file "${MNT}/etc/fstab" / >/dev/null

# Root only, as the partition task mounted it.
boot_options="$(findmnt --fstab --tab-file "${MNT}/etc/fstab" -no OPTIONS /boot)"
grep -qE '(^|,)fmask=0077(,|$)' <<<"$boot_options"
grep -qE '(^|,)dmask=0077(,|$)' <<<"$boot_options"

# fsck at boot needs a pass number and fsck.fat.
[ "$(findmnt --fstab --tab-file "${MNT}/etc/fstab" -no PASSNO /boot)" -gt 0 ]
[ -x "${MNT}/usr/bin/fsck.fat" ]
