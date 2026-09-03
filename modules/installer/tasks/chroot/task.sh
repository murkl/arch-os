# A shell inside the new system, with the terminal handed over for as long as it
# lasts. The one task that talks to the person in front of it.

simulating && return 0

clear
echo "You are now inside the new system at ${MNT}."
echo "Leave it again with 'exit'."
echo

# Never fatal: the shell exits with the status of the last command typed in it.
arch-chroot "$MNT" || true
