# The desktop reads the entry, and the entry restarts into one the boot loader
# lists: an ID that names nothing is refused by systemctl only after the
# question was answered.

arch-chroot "$MNT" desktop-file-validate "$RECOVERY_LAUNCHER"

entry="$(basename "$RECOVERY_EFI")"
grep -qF -- "--boot-loader-entry=${entry}" "${MNT}${RECOVERY_LAUNCHER}"
entries="$(arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short)"
grep -qF "\"id\":\"${entry}\"" <<<"$entries"
