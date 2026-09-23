[ "$(id -u)" -eq 0 ] && return 0
echo "This has to run as root. Log in as root and start it again." >&2
exit 1
