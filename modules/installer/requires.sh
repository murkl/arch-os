# WHAT A MACHINE HAS TO BE | Read by Oak before this module is offered at all
#
# Found by its own name, like everything else beside module.yaml, and the only
# thing Oak runs before a module has been opened. There are no answers yet, so
# it reads the machine and nothing else.
#
# A machine that is not a booted Arch Linux live image never sees this row:
# there is nothing here to install onto, and the module that writes the image it
# would be booted from is the one that belongs there instead.
#
# Here rather than in hooks/@preflight/ because the two answer different
# questions: this one decides whether the row exists at all, and preflight
# decides whether the machine behind the row is ready. A run started with
# --debug is offered every module, whatever this says.
#
# What goes to stderr is what somebody reads who named this module outright with
# --module=, so it says what is wrong and what to do about it, in that order.

arch_live && return 0
echo "The Installer runs from a booted Arch Linux live image. Write one with Create boot medium, start the machine from it, and open this there." >&2
exit 1
