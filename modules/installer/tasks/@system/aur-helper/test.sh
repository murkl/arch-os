# Run it, rather than look for the file: a helper that is there and does not
# start is the worse of the two failures, and the only one that survives to the
# finished machine. The -bin packages are linked against the pacman of the day
# they were published, so a libalpm that has moved on since leaves exactly that
# - an executable that exits 127 on every call.
#
# As the account, because paru refuses to run as root, and --version because it
# is the one call that needs neither network nor sudo. paru-bin and paru-git
# install the same command as paru does.
debugging && return 0

has_command "${ARCH_OS_AUR_HELPER%%-*}"
as_user "${ARCH_OS_AUR_HELPER%%-*} --version" >/dev/null
