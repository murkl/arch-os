# The clock the new system inherits is on network time.
timedatectl show -p NTP --value | grep -qx yes
