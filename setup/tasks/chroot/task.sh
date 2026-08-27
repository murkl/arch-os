# A shell inside the new system, with the terminal handed over for as long as it
# lasts. The one task that talks to the person in front of it — everything
# it prints is on their screen rather than in the log, because they are sitting
# in it.

simulating && return 0

clear
echo "You are now inside the new system at ${MNT}."
echo "Leave it again with 'exit'."
echo

# Never fatal: the shell exits with the status of the last command somebody
# typed in it, which says nothing at all about the installation.
arch-chroot "$MNT" || true
