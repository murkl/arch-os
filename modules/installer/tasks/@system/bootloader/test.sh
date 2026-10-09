# Both images under the names this system boots from, and an encrypted root
# that can be opened from inside them.
while read -r image; do
    [ -f "${MNT}${image}" ]
    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
        grep -q 'usr/lib/systemd/systemd-cryptsetup$' <<<"$contents"
    fi
done < <(boot_images)

# The loader as it reports itself, and the firmware's entry for it on this ESP
# rather than one an earlier installation left.
arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes
partuuid="$(lsblk -dno PARTUUID "$(boot_partition "$ARCH_OS_DISK")")"
[ -n "$partuuid" ]
efibootmgr | awk -v uuid="$partuuid" '
    { line = tolower($0) }
    index(line, tolower(uuid)) && index(line, "\\efi\\systemd\\systemd-bootx64.efi") { found = 1 }
    END { exit !found }'

# A console whose cursor the boot hides gets it back at the login.
if grep -qs 'vt.global_cursor_default=0' "${MNT}/etc/kernel/cmdline" "${MNT}/boot/loader/entries/main.conf"; then
    grep -qF '\e[?25h' "${MNT}/etc/issue.d/cursor.issue"
fi
