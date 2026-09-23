# sshd -t would be the stronger check, but it refuses to run without host keys,
# and those are generated at the first boot rather than here.

arch-chroot "$MNT" systemctl is-enabled sshd.service >/dev/null
