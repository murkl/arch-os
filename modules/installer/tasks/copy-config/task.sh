# The answers and the log, kept in the new system: what was installed, and what
# it said while doing it. The answers hold no password.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"

# The share-config task appends to this same file once there is an address to
# append, so the two must name it the same way.
cp -f "$MODULE_CONF" "${home}/installer.conf" 2>/dev/null || true

# Oak names the log after the module and keeps it beside the answers.
cp -f "${MODULE_CONF%.conf}.log" "${home}/installer.log" 2>/dev/null || true

own_home
