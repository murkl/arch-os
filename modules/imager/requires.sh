# WHAT A MACHINE HAS TO BE | Read by Oak before this module is offered at all
#
# Found by its own name, like everything else beside module.yaml, and the only
# thing Oak runs before a module has been opened. There are no answers yet, so
# it reads the machine and nothing else.
#
# The other way round from the Installer and the Recovery, which is the whole
# division between the three: they work on the machine the image booted, this
# one makes that image. A run started with --debug is offered every module,
# whatever this says.
#
# What goes to stderr is what somebody reads who named this module outright with
# --module=, so it says what is wrong and what to do about it, in that order.

on_live_image || return 0
echo "Create boot medium writes a device from an ordinary Linux machine. On the live image there is a machine to work on instead - open the Installer or the Recovery." >&2
exit 1
