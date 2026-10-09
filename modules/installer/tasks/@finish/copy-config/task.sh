# What was installed and what it said while doing it. The answers hold no
# password. actions/share-config appends its address to the same file.
home="${MNT}/home/${ARCH_OS_USERNAME}"
cp -f "$MODULE_CONF" "${home}/installer.conf" 2>/dev/null || true
cp -f "${MODULE_CONF%.conf}.log" "${home}/installer.log" 2>/dev/null || true
own_home
