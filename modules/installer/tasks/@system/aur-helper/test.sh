# Run it rather than look for the file: a helper that is there and does not
# start is the worse of the two failures, and the -bin packages fail exactly
# that way once Arch moves libalpm. As the account, because paru refuses to run
# as root, and --version because it needs neither network nor sudo.
debugging && return 0

has_command "${ARCH_OS_AUR_HELPER%%-*}"
as_user "${ARCH_OS_AUR_HELPER%%-*} --version" >/dev/null
