# Run as the account, since paru refuses root.
has_command paru
as_user "paru --version" >/dev/null

# The build's passwordless sudo is gone.
[ ! -e "${MNT}/etc/sudoers.d/99-aur-build" ]
