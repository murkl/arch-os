# What was installed and what it said while doing it. The answers hold no
# password. actions/share-config appends its address to the same file.
home="$(user_home)"
cp -f "$MODULE_CONF" "${home}/installer.conf" 2>/dev/null || true
cp -f "${MODULE_CONF%.conf}.log" "${home}/installer.log" 2>/dev/null || true
own_home

# The installation on the disk before the run says it is ready to start: the
# boot files on the FAT partition are left empty by a power cut otherwise.
sync
