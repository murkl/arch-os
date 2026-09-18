# The share is valid to samba itself, and something is there to announce it.
simulating && return 0

arch-chroot "$MNT" testparm -s >/dev/null 2>&1
arch-chroot "$MNT" systemctl is-enabled smb.service >/dev/null

# Asked of samba rather than of the file: what a file manager on the network
# shows is the value samba resolved, and a key it never read looks the same in
# the file as one it did.
[ "$(arch-chroot "$MNT" testparm -s --parameter-name='mdns name' 2>/dev/null)" = mdns ]
