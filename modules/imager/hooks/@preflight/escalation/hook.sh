# Not "are we root": this module deliberately is not — see as_root in the task
# that writes the device, which is the one step that needs it.
#
# What has to exist is a way to become root for that one step. Whether this
# particular person is allowed to is not asked here, because asking means asking
# for their password, and this stage runs before anybody has said they want to
# write anything. sudo says so itself, on the terminal the write step is handed,
# at the moment it is actually needed.

simulating && return 0

[ "$(id -u)" -eq 0 ] && return 0
command -v sudo >/dev/null && return 0
echo "Writing a device needs root, and this machine has no sudo to ask for it. Start this again as root." >&2
exit 1
