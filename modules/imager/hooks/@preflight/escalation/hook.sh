# Not "are we root": this module deliberately is not - see the task that writes
# the device. What has to exist is a way to become root for that one step.
#
# Whether this particular person may use sudo is not asked, because asking means
# asking for their password before anybody has said they want to write anything.
# sudo answers that itself, on the terminal, when the moment comes.

[ "$(id -u)" -eq 0 ] && return 0
command -v sudo >/dev/null && return 0
echo "Writing a device needs root, and this machine has no sudo to ask for it. Start this again as root." >&2
exit 1
