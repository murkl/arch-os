# Can this machine run a recovery at all? — see the hook.yaml beside this.

simulating && return 0

[ "$(id -u)" -eq 0 ] && return 0
echo "This has to run as root. Log in as root and start it again." >&2
exit 1
