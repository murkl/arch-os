# A shell inside the new system, with the terminal handed over for as long as it
# lasts. The one task that talks to the person in front of it.
#
# On the terminal itself rather than on this run's output: a shell draws its
# prompt on stderr and edits the line on stdout, and neither is the console here
# - the unit that starts the interface sends its errors to the journal, see
# iso/src/etc/systemd/system/arch-os.service. Inherited, the shell runs
# invisibly: no prompt, nothing echoed back, and a screen that looks stuck.
#
# And on a terminal of its own rather than on that one. An interactive shell
# takes the console's foreground process group for its own job control, and what
# it hands back when it leaves is the group this task runs in - which is gone
# the moment the task is. The interface is then in the background of the console
# it draws on: it can neither write to it nor read from it, the run stops there
# and the screen keeps the shell's last lines. `script` gives the shell a pty to
# do all of that on, so the console is never taken from the interface at all.

simulating && return 0

{
    clear
    echo "You are now inside the new system at ${MNT}."
    echo "Leave it again with 'exit'."
    echo

    # HOME, because a service has none and the shell that opens would then read
    # root's own configuration against an empty one: an error line about a file
    # at /, and none of the aliases or the prompt the account actually has.
    #
    # Never fatal: the shell exits with the status of the last command typed in it.
    HOME=/root script -qefc "arch-chroot ${MNT}" /dev/null || true
} <>/dev/tty >&0 2>&0
