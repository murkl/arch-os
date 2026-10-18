# The live system's clock follows at once, so the log reads in the zone of the
# machine being installed. Only the live system's /etc/localtime changes, the
# hardware clock is not written.
dry_run && return 0
timedatectl set-timezone "$ARCH_OS_TIMEZONE"
