clear
echo "You are now inside the system at ${MNT}."
echo "Leave it again with 'exit'."
echo

# HOME, because a service has none. The shell exits with whatever was typed last.
HOME=/root arch-chroot "$MNT" || true
