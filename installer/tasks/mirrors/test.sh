# The new system inherits the clock.
timedatectl show -p NTP --value | grep -qx yes
