arch-chroot "$MNT" systemctl is-enabled sshd.service >/dev/null

# The account logs in by key, owned by it and private.
keys="/home/${ARCH_OS_USERNAME}/.ssh/authorized_keys"
arch-chroot "$MNT" ssh-keygen -l -f "$keys" >/dev/null
[ "$(arch-chroot "$MNT" stat -c '%U %a' "$keys")" = "${ARCH_OS_USERNAME} 600" ]
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=ssh >/dev/null

# Read as sshd reads it, with a throwaway host key: the first boot makes the
# real ones. Outside /tmp, which arch-chroot mounts afresh.
dir="$(mktemp -d "${MNT}/var/tmp/sshd.XXXXXX")"
ssh-keygen -q -t ed25519 -N '' -f "${dir}/host"
effective="$(arch-chroot "$MNT" sshd -T -h "${dir#"$MNT"}/host")"
rm -rf "$dir"
grep -qix 'passwordauthentication no' <<<"$effective"
grep -qix 'kbdinteractiveauthentication no' <<<"$effective"
