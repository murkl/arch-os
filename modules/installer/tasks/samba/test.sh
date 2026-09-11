# The share is valid to samba itself, and something is there to announce it.
arch-chroot "$MNT" testparm -s >/dev/null 2>&1
arch-chroot "$MNT" systemctl is-enabled smb.service >/dev/null
