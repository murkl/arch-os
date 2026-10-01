# The Recovery among the applications, beside holding space at boot: one
# question, then a restart straight into it. systemd-boot starts that entry
# once, and the boot after it is the system again. logind lets whoever sits at
# the machine choose it without a password (set-reboot-to-boot-loader-entry).
#
# Translated the way a desktop entry is: its name in the file in every language
# this installer speaks, which the question is headed with (%c), and the
# question itself and its buttons are zenity's own.
# https://specifications.freedesktop.org/desktop-entry-spec/latest/exec-variables.html

# The desktop extras bring zenity, and a desktop without them does not.
chroot_pacman_install zenity

mkdir -p "$(dirname "${MNT}${RECOVERY_LAUNCHER}")"
render "$(where)/arch-os-recovery.desktop" ENTRY="$(basename "$RECOVERY_EFI")" >"${MNT}${RECOVERY_LAUNCHER}"
