# A shell inside the system being repaired, with the terminal handed over for as
# long as it lasts.

simulating && return 0

clear
echo "You are now inside the system on ${ARCH_OS_RECOVERY_DISK}, at ${MNT}."
echo "Leave it again with 'exit'."
echo

# Never fatal: the shell exits with the status of the last command typed in it.
arch-chroot "$MNT" || true
