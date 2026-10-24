# Both images exist, open an encrypted root and carry the restarting emergency
# drop-in.
emergency=etc/systemd/system/emergency.service.d/10-arch-os.conf
while read -r image; do
    [ -f "${MNT}${image}" ]
    contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
    grep -qxF "$emergency" <<<"$contents"
    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        grep -q 'usr/lib/systemd/systemd-cryptsetup$' <<<"$contents"
    fi
done < <(boot_images)

# With Secure Boot the kernel stays off the EFI partition, which nothing signs.
if [ "$(boot_kind)" = uki ] && [ -e "${MNT}/boot/vmlinuz-${KERNEL}" ]; then
    echo "the kernel lies on the EFI partition, where every rebuilt UKI would sign a swapped one" >&2
    exit 1
fi
[ -f "${MNT}$(kernel_image "$MNT" "$KERNEL")" ]

# systemd skips an unreadable line with only a warning and starts the shell
# nobody can use.
[ -z "$(unit_complaints emergency.service)" ]

# The firmware entry on this EFI partition, not one an earlier installation
# left.
arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes
partuuid="$(lsblk -dno PARTUUID "$(boot_partition "$ARCH_OS_DISK")")"
[ -n "$partuuid" ]
efibootmgr | awk -v uuid="$partuuid" '
    { line = tolower($0) }
    index(line, tolower(uuid)) && index(line, "\\efi\\systemd\\systemd-bootx64.efi") { found = 1 }
    END { exit !found }'

# The loader at the firmware entry's path and the fallback path, the signed copy
# where sbctl signed it.
loader=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
[ ! -f "${MNT}${loader}.signed" ] || loader="${loader}.signed"
cmp "${MNT}${loader}" "${MNT}/boot/EFI/systemd/systemd-bootx64.efi"
cmp "${MNT}${loader}" "${MNT}/boot/EFI/BOOT/BOOTX64.EFI"

# Both entries with boot tries, and no default, which the loader starts however
# often it fails.
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

# A hidden cursor comes back at the login.
if grep -qs 'vt.global_cursor_default=0' "${MNT}/etc/kernel/cmdline" "${entries}/main+${BOOT_TRIES}.conf"; then
    grep -qF '\e[?25h' "${MNT}/etc/issue.d/cursor.issue"
fi
