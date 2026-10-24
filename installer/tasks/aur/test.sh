# Run rather than looked for, as the account, since paru refuses root.
has_command paru
as_user "paru --version" >/dev/null

# The build's passwordless sudo went with it.
[ ! -e "${MNT}/etc/sudoers.d/99-aur-build" ]
