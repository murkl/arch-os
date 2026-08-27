# The answers and the log, kept in the new system: what was installed, how, and
# what it said while doing it. The answers file holds no password.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"

if cp -f "$INSTALLER_CONF" "${home}/installer.conf" 2>/dev/null; then
    # Which build of the installer produced this system, so the answers can be
    # read back years later against the right version of the tree.
    sed -i "1i\# Installed by Arch OS Installer ${INSTALLER_VERSION}" "${home}/installer.conf"
fi
cp -f "$INSTALLER_LOG" "${home}/installer.log" 2>/dev/null || true

arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
