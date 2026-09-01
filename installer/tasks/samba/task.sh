# File sharing the rest of the network can see, and the two discovery services
# that make this machine appear in it.
#
# The task that switches a service on is the task that installs it: wsdd is what
# Windows browses with, and it otherwise only arrives as a dependency of a GNOME
# package that could be left out tomorrow.

simulating && return 0

chroot_pacman_install samba wsdd

data="$(where)"

mkdir -p "${MNT}/etc/samba"
cp "${data}/smb.conf" "${MNT}/etc/samba/smb.conf"

if [ "$ARCH_OS_SAMBA_SHARE_ENABLED" = "true" ]; then
    cat "${data}/smb-shares.conf" >>"${MNT}/etc/samba/smb.conf"
fi

# Samba refuses to start on a broken file, so it is checked first.
arch-chroot "$MNT" testparm -s /etc/samba/smb.conf

if [ "$ARCH_OS_SAMBA_SHARE_ENABLED" = "true" ]; then
    arch-chroot "$MNT" mkdir -p /srv/samba/public
    arch-chroot "$MNT" chmod 777 /srv/samba/public
    arch-chroot "$MNT" chown -R nobody:users /srv/samba/public

    # Samba keeps its own password database, set to the same password.
    printf '%s\n%s\n' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" |
        arch-chroot "$MNT" smbpasswd -s -a "$ARCH_OS_USERNAME"
fi

# Windows finds the machine faster over IPv4 alone, and wsdd tries IPv6 first.
# A systemd drop-in rather than an edit of /etc/conf.d/wsdd, which belongs to
# the wsdd package: a drop-in is read after the unit's own environment file, so
# it wins, and there is nothing left to merge after an update.
# https://wiki.archlinux.org/title/Samba#Windows_1709_or_up_does_not_discover_the_samba_server_in_Network_view
mkdir -p "${MNT}/etc/systemd/system/wsdd.service.d"
{
    echo '# Written by the Arch OS Installer.'
    echo '[Service]'
    echo 'Environment=WSDD_PARAMS=-4'
} >"${MNT}/etc/systemd/system/wsdd.service.d/ipv4.conf"

arch-chroot "$MNT" systemctl enable smb.service
arch-chroot "$MNT" systemctl enable wsdd.service
