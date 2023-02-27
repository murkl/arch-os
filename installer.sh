#!/usr/bin/env bash

REPO_BASE_URL="https://raw.githubusercontent.com/murkl/arch-distro/main/"
WORKING_DIR="/tmp/arch-distro-wrapper"

download_file() {
    if ! mkdir -p "$(dirname "${WORKING_DIR}/${1}")"; then
        echo -e "ERROR: Create '$(dirname "${WORKING_DIR}/${1}")'"
        exit 1
    fi
    if ! curl -Lfs "${REPO_BASE_URL}/${1}" -o "${WORKING_DIR}/${1}"; then
        echo -e "ERROR: Downloading '${REPO_BASE_URL}/${1}'"
        exit 1
    fi
    # Make executable
    chmod +x "${WORKING_DIR}/${1}"
}

# When executed outside from Arch Live ISO
if [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ]; then
    download_file "tools/arch-creator.sh"
    bash -c "${WORKING_DIR}/tools/arch-creator.sh"
    exit $?
fi

# Print welcome and choose between Arch Install & Recovery
if whiptail --title "Arch Linux Installer" --yesno "Welcome to Arch Linux Installer!\n\nPlease choose whether you want to install Arch Linux or open Recovery to rescue your existing Arch Linux Installation." --yes-button "Install Arch" --no-button "Open Recovery" 20 80; then
    download_file "tools/arch-setup.sh"
    download_file "environment/gnome.sh"
    bash -c "${WORKING_DIR}/tools/arch-setup.sh"
else
    download_file "tools/arch-recovery.sh"
    bash -c "${WORKING_DIR}/tools/arch-recovery.sh"
fi
