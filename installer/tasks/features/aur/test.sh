# Run rather than looked for, as the account, since paru refuses root.
has_command paru
as_user "paru --version" >/dev/null
