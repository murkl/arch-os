# openssh is already on the system for the client; this only lets the server
# start. Its own configuration is left as Arch ships it: root cannot log in with
# a password, the account made here can.
# https://wiki.archlinux.org/title/OpenSSH#Server_usage

arch-chroot "$MNT" systemctl enable sshd.service
