# A record of the system, so beside its logs instead of in the home. The answer
# file holds no password, the script every command before this task.
dir="${MNT}/var/log/arch-os"
install -d -m 755 "$dir"
install -m 600 "$MODULE_CONF" "${dir}/installer.conf"
install -m 700 "$MODULE_SCRIPT" "${dir}/installer.sh"
# The copy ends with the outcome. Written directly, as printed output reaches
# the log only after the copy.
printf '%s INFO  Arch OS installed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$MODULE_LOG"
install -m 600 "$MODULE_LOG" "${dir}/installer.log"

# Flushed before the run reports success: a power cut otherwise leaves empty
# boot files on the EFI partition.
sync
