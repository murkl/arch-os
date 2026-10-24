# The answer file holds no password. The share-config action appends its URL
# to the copy.
home="$(user_home)"
cp -f "$MODULE_CONF" "${home}/installer.conf"
cp -f "$MODULE_LOG" "${home}/installer.log"
own_home

# Flushed before the run reports success: a power cut otherwise leaves empty
# boot files on the EFI partition.
sync
