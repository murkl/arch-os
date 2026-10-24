# Both images under the names this system boots from, an encrypted root that
# can be opened from inside them, and an emergency there that restarts.
emergency=etc/systemd/system/emergency.service.d/10-arch-os.conf
while read -r image; do
    [ -f "${MNT}${image}" ]
    contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
    grep -qxF "$emergency" <<<"$contents"
    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        grep -q 'usr/lib/systemd/systemd-cryptsetup$' <<<"$contents"
    fi
done < <(boot_images)

# systemd passes over a line it cannot read with a warning, and still starts the
# shell nobody can open.
[ -z "$(unit_complaints emergency.service)" ]

# The loader as it reports itself, and the firmware's entry for it on this ESP
# rather than one an earlier installation left.
arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes
partuuid="$(lsblk -dno PARTUUID "$(boot_partition "$ARCH_OS_DISK")")"
[ -n "$partuuid" ]
efibootmgr | awk -v uuid="$partuuid" '
    { line = tolower($0) }
    index(line, tolower(uuid)) && index(line, "\\efi\\systemd\\systemd-bootx64.efi") { found = 1 }
    END { exit !found }'

# The loader where the firmware's entry and its fallback path look, the signed
# one where sbctl signs it at its source.
loader=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
[ ! -f "${MNT}${loader}.signed" ] || loader="${loader}.signed"
cmp "${MNT}${loader}" "${MNT}/boot/EFI/systemd/systemd-bootx64.efi"
cmp "${MNT}${loader}" "${MNT}/boot/EFI/BOOT/BOOTX64.EFI"

# The system's two entries, each with its tries, and no default the loader
# would start however often it failed.
entries="${MNT}/boot/loader/entries"
[ -f "${entries}/main+${BOOT_TRIES}.conf" ]
[ -f "${entries}/main-fallback+${BOOT_TRIES}.conf" ]
if grep -q '^default' "${MNT}/boot/loader/loader.conf"; then
    echo "loader.conf names a default, which is started however often it fails" >&2
    exit 1
fi
listed="$(arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short)"
grep -qF '"id":"main.conf"' <<<"$listed"
grep -qF '"id":"main-fallback.conf"' <<<"$listed"
arch-chroot "$MNT" systemctl is-enabled arch-os-boot-tries.service >/dev/null

# A console whose cursor the boot hides gets it back at the login.
if grep -qs 'vt.global_cursor_default=0' "${MNT}/etc/kernel/cmdline" "${entries}/main+${BOOT_TRIES}.conf"; then
    grep -qF '\e[?25h' "${MNT}/etc/issue.d/cursor.issue"
fi
