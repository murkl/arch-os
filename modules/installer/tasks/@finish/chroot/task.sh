# A shell inside the new system, with the terminal handed over for as long as it
# lasts. The one task that talks to the person in front of it.
#
# On the terminal itself rather than on this run's output: a shell draws its
# prompt on stderr and edits the line on stdout, and neither is the console here
# - the unit that starts the interface sends its errors to the journal, see
# iso/src/etc/systemd/system/arch-os.service. Inherited, the shell runs
# invisibly: no prompt, nothing echoed back, and a screen that looks stuck.

simulating && return 0

{
    clear
    echo "You are now inside the new system at ${MNT}."
    echo "Leave it again with 'exit'."
    echo

    # Never fatal: the shell exits with the status of the last command typed in it.
    arch-chroot "$MNT" || true
} <>/dev/tty >&0 2>&0
