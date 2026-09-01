# A shell inside the system being repaired, with the terminal handed over for as
# long as it lasts. Everything it prints is on the screen of the person sitting
# in it rather than in the log — the same handover the installer makes at the
# end of an installation.

simulating && return 0

clear
echo "You are now inside the system on ${ARCH_OS_RECOVERY_DISK}, at ${MNT}."
echo "Leave it again with 'exit'."
echo

# Never fatal: the shell exits with the status of the last command somebody
# typed in it, which says nothing at all about the recovery.
arch-chroot "$MNT" || true
