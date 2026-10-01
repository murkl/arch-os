# Run rather than looked for, as the account, since paru refuses root.
has_command "$ARCH_OS_AUR_HELPER"
as_user "$ARCH_OS_AUR_HELPER --version" >/dev/null
