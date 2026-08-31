# Is there internet?
#
# Real HTTPS to a host that has to work for the install anyway, not a ping — a
# captive portal answers pings.

# The recovery downloads nothing, so there is nothing to connect for and no
# screen offering to.
[ "$INSTALLER_MODE" = "recovery" ] && return 0

is_online
