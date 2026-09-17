# WHAT A MACHINE HAS TO BE | Read by Oak before this module is offered at all
#
# Found by its own name, like everything else beside module.yaml, and the only
# thing Oak runs before a module has been opened. There are no answers yet, so
# it reads the machine and nothing else.
#
# The same rule the Installer carries, for the same reason: a system is repaired
# from outside itself, which means from a booted Arch Linux live image and from
# nowhere else. A run started with --debug is offered every module, whatever
# this says.
#
# What goes to stderr is what somebody reads who named this module outright with
# --module=, so it says what is wrong and what to do about it, in that order.

arch_live && return 0
echo "The Recovery runs from a booted Arch Linux live image. Write one with Create boot medium, start the machine from it, and open this there." >&2
exit 1
