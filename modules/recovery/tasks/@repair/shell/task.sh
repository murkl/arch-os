# A shell inside the system being repaired, with the terminal handed over for as
# long as it lasts.
#
# On the terminal itself rather than on this run's output: a shell draws its
# prompt on stderr and edits the line on stdout, and neither is the console here
# - see iso/src/etc/systemd/system/arch-os.service. Inherited, the shell runs
# invisibly: no prompt, nothing echoed back, and a screen that looks stuck.
#
# And on a terminal of its own rather than on that one. An interactive shell
# takes the console's foreground process group for its own job control and hands
# back the group this task runs in, which is gone the moment the task is - the
# interface would then be in the background of the console it draws on. `script`
# gives the shell a pty to do all of that on.

simulating && return 0

{
    clear
    echo "You are now inside the system on ${ARCH_OS_RECOVERY_DISK}, at ${MNT}."
    echo "Leave it again with 'exit'."
    echo

    # HOME, because a service has none and the shell would read root's own
    # configuration against an empty one. Never fatal: the shell exits with the
    # status of the last command typed in it.
    HOME=/root script -qefc "arch-chroot ${MNT}" /dev/null || true
} <>/dev/tty >&0 2>&0
