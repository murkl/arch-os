# The answers and the log, kept in the new system: what was installed, how, and
# what it said while doing it. The answers file holds no password.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"

# The share-config task appends to this same file once there is an address to
# append, so the two must name it the same way.
target="${home}/installer.conf"

if cp -f "$MODULE_CONF" "$target" 2>/dev/null; then
    # Which build produced this system, so the answers can be read back against
    # the right version of the module.
    sed -i "1i\# Installed by Arch OS Installer ${INSTALLER_VERSION}" "$target"
fi
cp -f "$MODULE_LOG" "${home}/installer.log" 2>/dev/null || true

arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
