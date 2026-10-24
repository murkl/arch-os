# sshd as Arch ships it, with keys only: docs/REFERENCE.md#firewall
# https://wiki.archlinux.org/title/OpenSSH#Server_usage
mkdir -p "${MNT}/etc/ssh/sshd_config.d"
render "$(where)/10-arch-os.conf" >"${MNT}/etc/ssh/sshd_config.d/10-arch-os.conf"
arch-chroot "$MNT" systemctl enable sshd.service

# Open in public, since a remote login comes from any network.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --add-service=ssh
fi

# The account's key, fetched where it is an address. Each line must be a key
# ssh reads.
keys="$ARCH_OS_SSH_KEY"
if [[ "$keys" == https://* ]]; then
    keys="$(fetch_url -sS --max-time 20 "$keys")" || exit 10
fi
dir="$(user_home)/.ssh"
mkdir -p "$dir"
printf '%s\n' "$keys" >"${dir}/authorized_keys"
chmod 700 "$dir"
chmod 600 "${dir}/authorized_keys"
own_home
ssh-keygen -l -f "${dir}/authorized_keys" >/dev/null || exit 10
