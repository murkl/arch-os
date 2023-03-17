#!/usr/bin/env bash
set -euo pipefail

# /////////////////////////////////////////////////////
# VARIABLES
# /////////////////////////////////////////////////////

MOUNT_RECOVERY="/mnt/recovery"
CRYPT_RECOVERY="cryptrecovery"

# /////////////////////////////////////////////////////
# TUI VARIABLES
# /////////////////////////////////////////////////////

TUI_TITLE="Arch Linux Recovery"
TUI_WIDTH="80"
TUI_HEIGHT="20"

# /////////////////////////////////////////////////////
# PRINT FUNCTIONS
# /////////////////////////////////////////////////////

print_green() { echo -e "\e[32m${1}\e[0m"; }
print_red() { echo -e "\e[31m${1}\e[0m"; }
print_yellow() { echo -e "\e[33m${1}\e[0m"; }

# ///////////////////////////////////////////////////////////////////
# UNMOUNT / TRAP
# ///////////////////////////////////////////////////////////////////

unmount() {
    set +e
    swapoff -a &>/dev/null
    umount -A -R "$MOUNT_RECOVERY" &>/dev/null
    cryptsetup close "$CRYPT_RECOVERY" &>/dev/null
    set -e
}

trap unmount EXIT

# /////////////////////////////////////////////////////
# OPEN RECOVERY
# /////////////////////////////////////////////////////

# Fetch Disks
disk_array=()
while read -r disk_line; do
    disk_array+=("/dev/$disk_line")
    disk_array+=(" ($(lsblk -d -n -o SIZE /dev/"$disk_line"))")
done < <(lsblk -I 8,259,254 -d -o KNAME -n)

if [ ${#disk_array[@]} == 0 ]; then
    whiptail --title "$TUI_TITLE" --msgbox "No Disk found" $TUI_HEIGHT $TUI_WIDTH
    exit 1
fi

# Select Disk
disk_result=$(whiptail --title "$TUI_TITLE" --menu "\nChoose Arch Linux Disk" $TUI_HEIGHT $TUI_WIDTH "${#disk_array[@]}" "${disk_array[@]}" 3>&1 1>&2 2>&3) || exit 1

[[ "$disk_result" = "/dev/nvm"* ]] && recovery_boot_partition="${disk_result}p1" || recovery_boot_partition="${disk_result}1"
[[ "$disk_result" = "/dev/nvm"* ]] && recovery_root_partition="${disk_result}p2" || recovery_root_partition="${disk_result}2"

# Ask for encryption
recovery_encryption_enabled="false"
whiptail --title "$TUI_TITLE" --yesno "Disk Encryption enabled?" $TUI_HEIGHT $TUI_WIDTH && recovery_encryption_enabled="true"

# Make sure everything is unmounted
unmount

# Create mount dir
mkdir -p "$MOUNT_RECOVERY" || exit 1
mkdir -p "$MOUNT_RECOVERY/boot" || exit 1

if [ "$recovery_encryption_enabled" = "true" ]; then

    # Encryption password
    recovery_encryption_password=$(whiptail --title "$TUI_TITLE" --passwordbox "\nEnter Ecnryption Password" $TUI_HEIGHT $TUI_WIDTH 3>&1 1>&2 2>&3) || exit 1

    # Open encrypted Disk
    echo -n "$recovery_encryption_password" | cryptsetup open "$recovery_root_partition" "$CRYPT_RECOVERY" || exit 1

    # Mount encrypted disk
    mount "/dev/mapper/${CRYPT_RECOVERY}" "$MOUNT_RECOVERY" || exit 1
    mount "$recovery_boot_partition" "$MOUNT_RECOVERY/boot" || exit 1

else
    # Mount unencrypted disk
    mount "$recovery_root_partition" "$MOUNT_RECOVERY" || exit 1
    mount "$recovery_boot_partition" "$MOUNT_RECOVERY/boot" || exit 1
fi

# Chroot
clear
echo -e "\n"
print_green "!! YOUR ARE NOW ON YOUR RECOVERY SYSTEM !!"
print_yellow "        Leave with command 'exit'         "
echo -e "\n"
arch-chroot "$MOUNT_RECOVERY" </dev/tty || exit 1
