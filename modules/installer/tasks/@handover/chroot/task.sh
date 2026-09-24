# A shell inside the new system, with the terminal handed over for as long as it
# lasts. Oak gives it the terminal itself and takes it back afterwards - see
# `tty:` in the Oak reference.

clear
echo "You are now inside the new system at ${MNT}."
echo "Leave it again with 'exit'."
echo

# HOME, because a service has none and the shell would read root's own
# configuration against an empty one. Never fatal: the shell exits with the
# status of the last command typed in it.
HOME=/root arch-chroot "$MNT" || true
