#!/usr/bin/env bash
set -euo pipefail

# /////////////////////////////////////////////////////
# VARIABLES
# /////////////////////////////////////////////////////

ARCH_ISO_DOWNLOAD_DIR="$HOME/Downloads"
ARCH_ISO_DOWNLOAD_URL="https://mirrors.xtom.de/archlinux/iso/latest"

# /////////////////////////////////////////////////////
# TUI VARIABLES
# /////////////////////////////////////////////////////

TUI_TITLE="Arch Linux USB Creator"
TUI_WIDTH="80"
TUI_HEIGHT="20"

# /////////////////////////////////////////////////////
# PRINT FUNCTIONS
# /////////////////////////////////////////////////////

print_green() { echo -e "\e[32m${1}\e[0m"; }
print_red() { echo -e "\e[31m${1}\e[0m"; }
print_purple() { echo -e "\e[35m${1}\e[0m"; }

print_title() {
    for ((i = ${#1}; i < 62; i++)); do local spaces="${spaces:-} "; done
    echo -e ""
    print_purple "┌───────────────────────────────────────────────────────────────────┐"
    print_purple "│ > ${1} ${spaces} │"
    print_purple "└───────────────────────────────────────────────────────────────────┘"
}

# /////////////////////////////////////////////////////
# OPEN USB CREATOR
# /////////////////////////////////////////////////////

# Print welcome screen
whiptail --title "$TUI_TITLE" --msgbox "Welcome to ${TUI_TITLE}!\n\nThis script will download the latest Arch ISO and will create a bootable USB Device." "$TUI_HEIGHT" "$TUI_WIDTH"

# Choose Disk
disk_array=()
while read -r disk_line; do
    disk_array+=("/dev/$disk_line")
    disk_array+=(" ($(lsblk -d -n -o SIZE /dev/"$disk_line"))")
done < <(lsblk -I 8 -d -o KNAME -n)

if [ ${#disk_array[@]} == 0 ]; then
    whiptail --title "$TUI_TITLE" --msgbox "No supported Disk found" $TUI_HEIGHT $TUI_WIDTH
    exit 1
fi

usb_disk=$(whiptail --title "$TUI_TITLE" --menu "\nChoose USB Target Device" $TUI_HEIGHT $TUI_WIDTH "${#disk_array[@]}" "${disk_array[@]}" 3>&1 1>&2 2>&3) || exit 1

# Clear screen
clear

# Download
arch_latest_version="$(curl -Lfs ${ARCH_ISO_DOWNLOAD_URL}/arch/version)"
arch_iso_file="archlinux-${arch_latest_version}-x86_64.iso"
arch_sha_file="sha256sums.txt"

mkdir -p "$ARCH_ISO_DOWNLOAD_DIR" || exit 1

# Downloading ISO
if ! [ -f "${ARCH_ISO_DOWNLOAD_DIR}/${arch_iso_file}" ]; then
    print_title "Downloading Arch Linux ISO..."
    if ! curl -Lf --progress-bar "${ARCH_ISO_DOWNLOAD_URL}/${arch_iso_file}" -o "${ARCH_ISO_DOWNLOAD_DIR}/${arch_iso_file}.part"; then
        print_red "ERROR: Downloading Arch ISO"
        exit 1
    fi
    if ! mv "${ARCH_ISO_DOWNLOAD_DIR}/${arch_iso_file}.part" "${ARCH_ISO_DOWNLOAD_DIR}/${arch_iso_file}"; then
        print_red "ERROR: Moving Arch ISO"
        exit 1
    fi
fi

# Check ISO
print_title "Check Arch Linux ISO"

# Downloading Checksum
if ! curl -Lfs "${ARCH_ISO_DOWNLOAD_URL}/${arch_sha_file}" -o "${ARCH_ISO_DOWNLOAD_DIR}/${arch_sha_file}"; then
    print_red "ERROR: Downloading Checksum"
    exit 1
fi

cd "$ARCH_ISO_DOWNLOAD_DIR" || exit 1
if grep -qrnw "${arch_sha_file}" -e "$(sha256sum "${arch_iso_file}")"; then
    rm -f "$ARCH_ISO_DOWNLOAD_DIR/${arch_sha_file}"
    print_green "Checksum correct"
else
    print_red "ERROR: Checksum incorrect"
    exit 1
fi

# Create USB Device
print_title "Create Bootable USB Device..."
if ! sudo dd bs=4M if="${arch_iso_file}" of="$usb_disk" status=progress oflag=sync; then
    print_red "ERROR: Creating USB Device"
    exit 1
fi

# Finished
print_title "Finished"
print_green "Please remove USB Device: $usb_disk"
