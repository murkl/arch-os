# openssh is already on the system for the client; this only lets the server
# start. Its own configuration is left as Arch ships it: root cannot log in with
# a password, the account made here can.
# https://wiki.archlinux.org/title/OpenSSH#Server_usage

arch-chroot "$MNT" systemctl enable sshd.service

# Reachable on every network, since logging in from another machine is what was
# asked for: public is where every network lands until it is marked, and home
# lets ssh in as firewalld ships it.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --add-service=ssh
fi
