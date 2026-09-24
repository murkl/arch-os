# A machine that will not boot is the one failure nothing later makes up for, so
# what is checked is the loader as it reports itself from inside the new system.

arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes

# And the firmware's own entry for it, on this ESP rather than one an earlier
# installation left behind. A loader on the disk that the firmware has no entry
# for boots only as long as nothing else claims the fallback path.
partuuid="$(lsblk -dno PARTUUID "$BOOT_PART")"
[ -n "$partuuid" ]
efibootmgr | awk -v uuid="$partuuid" '
    { line = tolower($0) }
    index(line, tolower(uuid)) && index(line, "\\efi\\systemd\\systemd-bootx64.efi") { found = 1 }
    END { exit !found }'
