#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------------------------------------------------------------------------------
# SCRIPT VARIABLES
# ----------------------------------------------------------------------------------------------------

# Version
VERSION='1.0.7'

# Title
TITLE="Arch OS Installer ${VERSION}"

# Config file (sourced if exists)
INSTALLER_CONFIG="./installer.conf"

# Logfile (created during install)
LOG_FILE="./installer.log"

# TUI width
TUI_WIDTH="80"

# TUI height
TUI_HEIGHT="20"

# TUI state
TUI_POSITION=""

# Whiptail progress count
PROGRESS_COUNT=0

# Whiptail total processes (number of occurrences of print_whiptail_info - 3)
PROGRESS_TOTAL=33

# ----------------------------------------------------------------------------------------------------
# INSTALLATION VARIABLES
# ----------------------------------------------------------------------------------------------------

ARCH_OS_USERNAME=""
ARCH_OS_HOSTNAME=""
ARCH_OS_PASSWORD=""
ARCH_OS_DISK=""
ARCH_OS_BOOT_PARTITION=""
ARCH_OS_ROOT_PARTITION=""
ARCH_OS_ENCRYPTION_ENABLED=""
ARCH_OS_SWAP_SIZE=""
ARCH_OS_REFLECTOR_COUNTRY=""
ARCH_OS_TIMEZONE=""
ARCH_OS_LOCALE_LANG=""
ARCH_OS_LOCALE_GEN_LIST=()
ARCH_OS_VCONSOLE_KEYMAP=""
ARCH_OS_VCONSOLE_FONT=""
ARCH_OS_X11_KEYBOARD_LAYOUT=""
ARCH_OS_X11_KEYBOARD_VARIANT=""
ARCH_OS_BOOTSPLASH_ENABLED=""
ARCH_OS_GNOME_ENABLED=""
ARCH_OS_KERNEL=""
ARCH_OS_MICROCODE=""

# ----------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ----------------------------------------------------------------------------------------------------

if ! command -v whiptail &>/dev/null; then
    echo "ERROR: whiptail not found" >&2
    exit 1
fi

# ----------------------------------------------------------------------------------------------------
# PRINT FUNCTIONS
# ----------------------------------------------------------------------------------------------------

print_menu_entry() {
    local key="$1"
    local val="$2" && val=$(echo "$val" | xargs) # Trim spaces
    local spaces=""
    # Locate spaces
    for ((i = ${#key}; i < 12; i++)); do spaces="${spaces} "; done
    [ -z "$val" ] && val='?' # Set default value
    # Print menu entry text
    echo "${key} ${spaces} ->  $val"
}

print_whiptail_info() {
    # Print info to stderr in case of failure (only stderr will be logged)
    echo "###!CMD" >&2  # Print marker for logging
    echo ">>> ${1}" >&2 # Print title for logging
    # Print percent & info for whiptail (uses descriptor 3 as stdin)
    ((PROGRESS_COUNT += 1)) && echo -e "XXX\n$((PROGRESS_COUNT * 100 / PROGRESS_TOTAL))\n${1}...\nXXX" >&3
}

# ----------------------------------------------------------------------------------------------------
# CONFIG FUNCTIONS
# ----------------------------------------------------------------------------------------------------

check_config() {

    # Set default values (if not already set)
    [ -z "$ARCH_OS_HOSTNAME" ] && ARCH_OS_HOSTNAME="arch-os"
    [ -z "$ARCH_OS_KERNEL" ] && ARCH_OS_KERNEL="linux-zen"
    #[ -z "$ARCH_OS_VCONSOLE_FONT" ] && ARCH_OS_VCONSOLE_FONT="eurlatgr"
    #[ -z "$ARCH_OS_REFLECTOR_COUNTRY" ] && ARCH_OS_REFLECTOR_COUNTRY="Germany,France"

    [ -z "${ARCH_OS_USERNAME}" ] && TUI_POSITION="user" && return 1
    [ -z "${ARCH_OS_PASSWORD}" ] && TUI_POSITION="password" && return 1
    [ -z "${ARCH_OS_TIMEZONE}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_OS_LOCALE_LANG}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_OS_LOCALE_GEN_LIST[*]}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_OS_VCONSOLE_KEYMAP}" ] && TUI_POSITION="keyboard" && return 1
    [ -z "${ARCH_OS_DISK}" ] && TUI_POSITION="disk" && return 1
    [ -z "${ARCH_OS_BOOT_PARTITION}" ] && TUI_POSITION="disk" && return 1
    [ -z "${ARCH_OS_ROOT_PARTITION}" ] && TUI_POSITION="disk" && return 1
    [ -z "${ARCH_OS_ENCRYPTION_ENABLED}" ] && TUI_POSITION="encrypt" && return 1
    [ -z "${ARCH_OS_SWAP_SIZE}" ] && TUI_POSITION="swap" && return 1
    [ -z "${ARCH_OS_BOOTSPLASH_ENABLED}" ] && TUI_POSITION="plymouth" && return 1
    [ -z "${ARCH_OS_GNOME_ENABLED}" ] && TUI_POSITION="gnome" && return 1
    TUI_POSITION="install"
}

create_config() {
    {
        echo "# ${TITLE} (generated: $(date --utc '+%Y-%m-%d %H:%M') UTC)"
        echo ""
        echo "# Hostname (auto)"
        echo "ARCH_OS_HOSTNAME='${ARCH_OS_HOSTNAME}'"
        echo ""
        echo "# User (mandatory)"
        echo "ARCH_OS_USERNAME='${ARCH_OS_USERNAME}'"
        echo ""
        echo "# Disk (mandatory)"
        echo "ARCH_OS_DISK='${ARCH_OS_DISK}'"
        echo ""
        echo "# Boot partition (auto)"
        echo "ARCH_OS_BOOT_PARTITION='${ARCH_OS_BOOT_PARTITION}'"
        echo ""
        echo "# Root partition (auto)"
        echo "ARCH_OS_ROOT_PARTITION='${ARCH_OS_ROOT_PARTITION}'"
        echo ""
        echo "# Disk encryption (mandatory)"
        echo "ARCH_OS_ENCRYPTION_ENABLED='${ARCH_OS_ENCRYPTION_ENABLED}'"
        echo ""
        echo "# Swap (mandatory): 0 or null = disable"
        echo "ARCH_OS_SWAP_SIZE='${ARCH_OS_SWAP_SIZE}'"
        echo ""
        echo "# Bootsplash (mandatory)"
        echo "ARCH_OS_BOOTSPLASH_ENABLED='${ARCH_OS_BOOTSPLASH_ENABLED}'"
        echo ""
        echo "# GNOME Desktop (mandatory): false = minimal arch"
        echo "ARCH_OS_GNOME_ENABLED='${ARCH_OS_GNOME_ENABLED}'"
        echo ""
        echo "# Timezone (auto): ls /usr/share/zoneinfo/**"
        echo "ARCH_OS_TIMEZONE='${ARCH_OS_TIMEZONE}' # example: Europe/Berlin"
        echo ""
        echo "# Country used by reflector (optional)"
        echo "ARCH_OS_REFLECTOR_COUNTRY='${ARCH_OS_REFLECTOR_COUNTRY}' # example: Germany,France"
        echo ""
        echo "# Locale (mandatory): ls /usr/share/i18n/locales"
        echo "ARCH_OS_LOCALE_LANG='${ARCH_OS_LOCALE_LANG}' # example: de_DE"
        echo ""
        echo "# Locale List (auto): cat /etc/locale.gen"
        echo "ARCH_OS_LOCALE_GEN_LIST=(${ARCH_OS_LOCALE_GEN_LIST[*]@Q})"
        echo ""
        echo "# Console keymap (mandatory): localectl list-keymaps"
        echo "ARCH_OS_VCONSOLE_KEYMAP='${ARCH_OS_VCONSOLE_KEYMAP}' # example de-latin1-nodeadkeys"
        echo ""
        echo "# Console font (optional): find /usr/share/kbd/consolefonts/*.psfu.gz"
        echo "ARCH_OS_VCONSOLE_FONT='${ARCH_OS_VCONSOLE_FONT}' # example: eurlatgr"
        echo ""
        echo "# X11 keyboard layout (mandatory): localectl list-x11-keymap-layouts"
        echo "ARCH_OS_X11_KEYBOARD_LAYOUT='${ARCH_OS_X11_KEYBOARD_LAYOUT}' # example: de"
        echo ""
        echo "# X11 keyboard variant (optional): localectl list-x11-keymap-variants"
        echo "ARCH_OS_X11_KEYBOARD_VARIANT='${ARCH_OS_X11_KEYBOARD_VARIANT}' # example: nodeadkeys"
        echo ""
        echo "# Kernel (mandatory)"
        echo "ARCH_OS_KERNEL='${ARCH_OS_KERNEL}' # linux, linux-lts linux-zen, linux-hardened"
    } >"$INSTALLER_CONFIG"
}

# ----------------------------------------------------------------------------------------------------
# SETUP FUNCTIONS
# ----------------------------------------------------------------------------------------------------

tui_set_language() {

    # Set timezone
    [ -z "$ARCH_OS_TIMEZONE" ] && ARCH_OS_TIMEZONE="$(curl -s http://ip-api.com/line?fields=timezone)"
    local user_input="$ARCH_OS_TIMEZONE"
    user_input=$(whiptail --title "$TITLE" --inputbox "\nSet Timezone (auto)" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)
    if [ ! -f "/usr/share/zoneinfo/${user_input}" ]; then
        whiptail --title "$TITLE" --msgbox "Error: Timezone '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    else
        ARCH_OS_TIMEZONE="$user_input"
    fi

    # Set locale
    local user_input="$ARCH_OS_LOCALE_LANG"
    [ -z "$user_input" ] && user_input='en_US'
    user_input=$(whiptail --title "$TITLE" --inputbox "\nPlease insert locale\n\nExample: 'en_US' or 'de_DE'" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)
    # shellcheck disable=SC2001
    if [ -z "$user_input" ] || ! grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<<"$user_input") " /etc/locale.gen; then
        whiptail --title "$TITLE" --msgbox "Error: Locale '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    else
        ARCH_OS_LOCALE_LANG="$user_input"
    fi

    # Set locale.gen properties (auto generate ARCH_OS_LOCALE_GEN_LIST)
    ARCH_OS_LOCALE_GEN_LIST=()
    while read -r locale_entry; do
        ARCH_OS_LOCALE_GEN_LIST+=("$locale_entry")
    done < <(sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "${ARCH_OS_LOCALE_LANG}")
    # Add fallback
    [[ "${ARCH_OS_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && ARCH_OS_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')

    # Success
    return 0
}

tui_set_keyboard() {

    # Input console keyboard keymap
    local user_input="$ARCH_OS_VCONSOLE_KEYMAP"
    [ -z "$user_input" ] && user_input='us'
    user_input=$(whiptail --title "$TITLE" --inputbox "\nPlease insert console keyboard keymap\n\nExample: 'de-latin1-nodeadkeys' or 'us'" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

    # Check & set console keymap
    if ! localectl list-keymaps | grep -Fxq "$user_input"; then
        whiptail --title "$TITLE" --msgbox "Error: Keyboard layout '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    else
        ARCH_OS_VCONSOLE_KEYMAP="$user_input"
    fi

    # Success
    return 0
}

tui_set_user() {
    ARCH_OS_USERNAME=$(whiptail --title "$TITLE" --inputbox "\nEnter Username" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_OS_USERNAME" 3>&1 1>&2 2>&3)
    if [ -z "$ARCH_OS_USERNAME" ]; then
        whiptail --title "$TITLE" --msgbox "Error: Username is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    fi
    # Success
    return 0
}

tui_set_password() {
    ARCH_OS_PASSWORD=$(whiptail --title "$TITLE" --passwordbox "\nEnter Password" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
    if [ -z "$ARCH_OS_PASSWORD" ]; then
        whiptail --title "$TITLE" --msgbox "Error: Password is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    fi

    local password_check
    password_check=$(whiptail --title "$TITLE" --passwordbox "\nEnter Password (again)" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
    if [ "$ARCH_OS_PASSWORD" != "$password_check" ]; then
        ARCH_OS_PASSWORD=""
        whiptail --title "$TITLE" --msgbox "Error: Password not identical" "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    fi
    # Success
    return 0
}

tui_set_disk() {
    # List available disks
    disk_array=()
    while read -r disk_line; do
        disk_array+=("/dev/$disk_line")
        disk_array+=(" ($(lsblk -d -n -o SIZE /dev/"$disk_line"))")
    done < <(lsblk -I 8,259,254 -d -o KNAME -n)

    # If no disk found
    [ "${#disk_array[@]}" = "0" ] && whiptail --title "$TITLE" --msgbox "No Disk found" "$TUI_HEIGHT" "$TUI_WIDTH" && return 1

    # Show TUI (select disk)
    ARCH_OS_DISK=$(whiptail --title "$TITLE" --menu "\nChoose Installation Disk" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "${#disk_array[@]}" "${disk_array[@]}" 3>&1 1>&2 2>&3)

    # Handle result
    [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}p1" || ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}1"
    [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}p2" || ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}2"

    # Success
    return 0
}

tui_set_encryption() {
    ARCH_OS_ENCRYPTION_ENABLED="false"
    if whiptail --title "$TITLE" --yesno "Enable Disk Encryption?" --defaultno "$TUI_HEIGHT" "$TUI_WIDTH"; then
        ARCH_OS_ENCRYPTION_ENABLED="true"
    fi
    # Success
    return 0
}

tui_set_swap() {
    ARCH_OS_SWAP_SIZE="$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 + 1))"
    ARCH_OS_SWAP_SIZE=$(whiptail --title "$TITLE" --inputbox "\nEnter Swap Size in GB (0 = disable, ${ARCH_OS_SWAP_SIZE} = recommended)" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_OS_SWAP_SIZE" 3>&1 1>&2 2>&3)
    if [ -z "$ARCH_OS_SWAP_SIZE" ]; then
        whiptail --title "$TITLE" --msgbox "Error: Swap is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    fi
    # Success
    return 0
}

tui_set_plymouth() {
    ARCH_OS_BOOTSPLASH_ENABLED="false"
    if whiptail --title "$TITLE" --yesno "Install Bootsplash Animation (plymouth)?" --yes-button "Yes" --no-button "No" "$TUI_HEIGHT" "$TUI_WIDTH"; then
        ARCH_OS_BOOTSPLASH_ENABLED="true"
    fi
    # Success
    return 0
}

tui_set_gnome() {
    ARCH_OS_GNOME_ENABLED="false"
    if whiptail --title "$TITLE" --yesno "Install GNOME Desktop?" --yes-button "GNOME Desktop" --no-button "Minimal Arch" "$TUI_HEIGHT" "$TUI_WIDTH"; then

        # Set X11 keyboard layout
        local user_input="$ARCH_OS_X11_KEYBOARD_LAYOUT"
        [ -z "$user_input" ] && user_input='us'
        user_input=$(whiptail --title "$TITLE" --inputbox "\nPlease insert X11 (Xorg) keyboard layout\n\nExample: 'de' or 'us'" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)
        ARCH_OS_X11_KEYBOARD_LAYOUT="$user_input"

        # Set X11 keyboard variant
        local user_input="$ARCH_OS_X11_KEYBOARD_VARIANT"
        [ -z "$user_input" ] && user_input='nodeadkeys'
        user_input=$(whiptail --title "$TITLE" --inputbox "\nPlease insert X11 (Xorg) keyboard variant\n\nExample: 'nodeadkeys' or leave empty for default" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)
        ARCH_OS_X11_KEYBOARD_VARIANT="$user_input"

        # Set GNOME
        ARCH_OS_GNOME_ENABLED="true"
    fi

    # Success
    return 0
}

# ----------------------------------------------------------------------------------------------------
# INIT CONFIG
# ----------------------------------------------------------------------------------------------------

# shellcheck disable=SC1090
[ -f "$INSTALLER_CONFIG" ] && source "$INSTALLER_CONFIG"
check_config || true # Check and init properties
create_config        # Generate properties

# ----------------------------------------------------------------------------------------------------
# WAIT & SLEEP
# ----------------------------------------------------------------------------------------------------

wait && sleep 0.8

# ----------------------------------------------------------------------------------------------------
# WELCOME SCREEN
# ----------------------------------------------------------------------------------------------------

welcome_txt="
           █████  ██████   ██████ ██   ██      ██████  ███████ 
          ██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
          ███████ ██████  ██      ███████     ██    ██ ███████ 
          ██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
          ██   ██ ██   ██  ██████ ██   ██      ██████  ███████ 
                                 

      Welcome to Arch OS Installer. Please hit <ENTER> to continue...
"
whiptail --title "$TITLE" --msgbox "$welcome_txt" "$TUI_HEIGHT" "$TUI_WIDTH"

# ----------------------------------------------------------------------------------------------------
# SHOW MENU
# ----------------------------------------------------------------------------------------------------

while (true); do

    # Source user properties
    # shellcheck disable=SC1090
    [ -f "$INSTALLER_CONFIG" ] && source "$INSTALLER_CONFIG"

    # Check config entries and set menu position
    check_config || true

    # Create TUI menu entries
    menu_entry_array=()
    menu_entry_array+=("user") && menu_entry_array+=("$(print_menu_entry "User" "${ARCH_OS_USERNAME}")")
    menu_entry_array+=("password") && menu_entry_array+=("$(print_menu_entry "Password" "$([ -n "$ARCH_OS_PASSWORD" ] && echo "******")")")
    menu_entry_array+=("language") && menu_entry_array+=("$(print_menu_entry "Language" "  ${ARCH_OS_LOCALE_LANG}")")
    menu_entry_array+=("keyboard") && menu_entry_array+=("$(print_menu_entry "Keyboard" "  ${ARCH_OS_VCONSOLE_KEYMAP}")")
    menu_entry_array+=("disk") && menu_entry_array+=("$(print_menu_entry "Disk" "${ARCH_OS_DISK}")")
    menu_entry_array+=("encrypt") && menu_entry_array+=("$(print_menu_entry "Encryption" "${ARCH_OS_ENCRYPTION_ENABLED}")")
    menu_entry_array+=("swap") && menu_entry_array+=("$(print_menu_entry "Swap" "$([ -n "$ARCH_OS_SWAP_SIZE" ] && { [ "$ARCH_OS_SWAP_SIZE" != "0" ] && echo "${ARCH_OS_SWAP_SIZE} GB" || echo "disabled"; })")")
    menu_entry_array+=("plymouth") && menu_entry_array+=("$(print_menu_entry "Bootsplash" "${ARCH_OS_BOOTSPLASH_ENABLED}")")
    menu_entry_array+=("gnome") && menu_entry_array+=("$(print_menu_entry "GNOME" "${ARCH_OS_GNOME_ENABLED}")")
    menu_entry_array+=("") && menu_entry_array+=("") # Empty entry
    menu_entry_array+=("edit") && menu_entry_array+=("> Edit manually")
    if [ "$TUI_POSITION" = "install" ]; then
        menu_entry_array+=("install") && menu_entry_array+=("> Continue Installation")
    else
        menu_entry_array+=("install") && menu_entry_array+=("x Config incomplete")
    fi

    # Open TUI menu
    menu_selection=$(whiptail --title "$TITLE" --menu "\n" --ok-button "Ok" --cancel-button "Exit" --notags --default-item "$TUI_POSITION" "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#menu_entry_array[@]} / 2) + (${#menu_entry_array[@]} % 2)))" "${menu_entry_array[@]}" 3>&1 1>&2 2>&3) || exit

    # Handle result
    case "${menu_selection}" in

    "user")
        tui_set_user || continue
        create_config
        ;;
    "password")
        tui_set_password || continue
        create_config
        ;;
    "language")
        tui_set_language || continue
        create_config
        ;;
    "keyboard")
        tui_set_keyboard || continue
        create_config
        ;;
    "disk")
        tui_set_disk || continue
        create_config
        ;;
    "encrypt")
        tui_set_encryption || continue
        create_config
        ;;
    "swap")
        tui_set_swap || continue
        create_config
        ;;
    "plymouth")
        tui_set_plymouth || continue
        create_config
        ;;
    "gnome")
        tui_set_gnome || continue
        create_config
        ;;
    "edit")
        nano "$INSTALLER_CONFIG" </dev/tty
        continue
        ;;
    "install")
        check_config || continue
        if whiptail --title "$TITLE" --yesno "> Installation Properties\n\n$(head -100 "$INSTALLER_CONFIG" | tail +3)" --defaultno --yes-button "Edit" --no-button "Continue" --scrolltext "$TUI_HEIGHT" "$TUI_WIDTH"; then
            nano "$INSTALLER_CONFIG" </dev/tty
            continue # Open main menu for check again
        fi
        break # Break loop and continue installation
        ;;
    *) continue ;; # Do nothing and continue loop

    esac

done

# ----------------------------------------------------------------------------------------------------
# ASK FOR INSTALLATION
# ----------------------------------------------------------------------------------------------------

if ! whiptail --title "$TITLE" --yesno "Start Arch OS Linux Installation?\n\nAll data on ${ARCH_OS_DISK} will be DELETED!" --defaultno --yes-button "Start Installation" --no-button "Exit" "$TUI_HEIGHT" "$TUI_WIDTH"; then
    exit 1
fi

# ----------------------------------------------------------------------------------------------------
# TRAP / LOGGING
# ----------------------------------------------------------------------------------------------------

# shellcheck disable=SC2317
trap_exit() {

    # Result code
    local result_code="$?"

    # Duration
    local duration=$SECONDS
    local duration_min="$((duration / 60))"
    local duration_sec="$((duration % 60))"

    # Check exit return code
    if [ "$result_code" -gt 0 ]; then # Error >= 1

        # Read Logs
        local logs=""
        local line=""
        while read -r line; do
            [ "$line" = "###!CMD" ] && break # If first marker (from bottom) found, break loop
            [ -z "$line" ] && continue       # Skip newline
            logs="${logs}\n${line}"          # Append log
        done <<<"$(tac "$LOG_FILE")"         # Read logfile inverted (from bottom)

        # Show TUI (duration & log)
        whiptail --title "$TITLE" --msgbox "Arch OS Installation failed.\n\nDuration: ${duration_min} minutes and ${duration_sec} seconds\n\n$(echo -e "$logs" | tac)" --scrolltext 30 90

    else # Success = 0
        # Show TUI (duration time)
        whiptail --title "$TITLE" --msgbox "Arch OS Installation successful.\n\nDuration: ${duration_min} minutes and ${duration_sec} seconds" "$TUI_HEIGHT" "$TUI_WIDTH"

        # Unmount
        wait # Wait for sub processes
        swapoff -a
        umount -A -R /mnt
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot

        if whiptail --title "$TITLE" --yesno "Reboot now?" --defaultno --yes-button "Yes" --no-button "No" "$TUI_HEIGHT" "$TUI_WIDTH"; then
            wait && reboot
        fi
    fi

    # Exit
    exit "$result_code"
}

# ----------------------------------------------------------------------------------------------------
# INSTALLATION
# ----------------------------------------------------------------------------------------------------

# Set trap for logging on exit
trap 'trap_exit $?' EXIT

# Messure execution time
SECONDS=0

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////  START ARCH LINUX INSTALLATION //////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

(
    # Print nothing from stdin & stderr to console
    exec 3>&1 4>&2     # Saves file descriptors (new stdin: &3 new stderr: &4)
    exec 1>/dev/null   # Log stdin to /dev/null
    exec 2>"$LOG_FILE" # Log stderr to logfile

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Checkup"
    # ----------------------------------------------------------------------------------------------------

    [ ! -d /sys/firmware/efi ] && echo "ERROR: BIOS not supported! Please set your boot mode to UEFI." >&2 && exit 1
    [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && echo "ERROR: You must execute the Installer from Arch ISO!" >&2 && exit 1

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Waiting for Reflector from Arch ISO"
    # ----------------------------------------------------------------------------------------------------

    # This mirrorlist will copied to new Arch system during installation
    while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
    pgrep reflector &>/dev/null && echo "ERROR: Reflector timeout after 180 seconds" >&2 && exit 1

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Prepare Installation"
    # ----------------------------------------------------------------------------------------------------

    # Sync clock
    timedatectl set-ntp true

    # Make sure everything is unmounted before start install
    swapoff -a &>/dev/null || true
    umount -A -R /mnt &>/dev/null || true
    cryptsetup close cryptroot &>/dev/null || true
    vgchange -an || true

    # Temporarily disable ECN (prevent traffic problems with some old routers)
    #sysctl net.ipv4.tcp_ecn=0

    # Update keyring
    pacman -Sy --noconfirm --disable-download-timeout archlinux-keyring

    # Detect microcode if empty
    if [ -z "$ARCH_OS_MICROCODE" ]; then
        grep -E "GenuineIntel" <<<"$(lscpu)" && ARCH_OS_MICROCODE="intel-ucode"
        grep -E "AuthenticAMD" <<<"$(lscpu)" && ARCH_OS_MICROCODE="amd-ucode"
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Wipe & Create Partitions (${ARCH_OS_DISK})"
    # ----------------------------------------------------------------------------------------------------

    # Wipe all partitions
    wipefs -af "$ARCH_OS_DISK"

    # Create new GPT partition table
    sgdisk -o "$ARCH_OS_DISK"

    # Create partition /boot efi partition: 1 GiB
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot "$ARCH_OS_DISK"

    # Create partition / partition: Rest of space
    sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$ARCH_OS_DISK"

    # Reload partition table
    partprobe "$ARCH_OS_DISK"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable Disk Encryption"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        echo -n "$ARCH_OS_PASSWORD" | cryptsetup luksFormat "$ARCH_OS_ROOT_PARTITION"
        echo -n "$ARCH_OS_PASSWORD" | cryptsetup open "$ARCH_OS_ROOT_PARTITION" cryptroot
    else
        echo "> Skipped"
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Format Disk"
    # ----------------------------------------------------------------------------------------------------

    mkfs.fat -F 32 -n BOOT "$ARCH_OS_BOOT_PARTITION"
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && mkfs.ext4 -F -L ROOT /dev/mapper/cryptroot
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && mkfs.ext4 -F -L ROOT "$ARCH_OS_ROOT_PARTITION"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Mount Disk"
    # ----------------------------------------------------------------------------------------------------

    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && mount -v /dev/mapper/cryptroot /mnt
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && mount -v "$ARCH_OS_ROOT_PARTITION" /mnt
    mkdir -p /mnt/boot
    mount -v "$ARCH_OS_BOOT_PARTITION" /mnt/boot

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Pacstrap System Packages (This may take a while ~ 10 min)"
    # ----------------------------------------------------------------------------------------------------

    packages=()
    packages+=("base")
    packages+=("base-devel")
    packages+=("${ARCH_OS_KERNEL}")
    packages+=("linux-firmware")
    packages+=("networkmanager")
    packages+=("pacman-contrib")
    packages+=("reflector")
    packages+=("git")
    packages+=("nano")
    packages+=("bash-completion")
    packages+=("pkgfile")
    [ -n "$ARCH_OS_MICROCODE" ] && packages+=("$ARCH_OS_MICROCODE")

    # Install core and initialize an empty pacman keyring in the target
    pacstrap -K /mnt "${packages[@]}" "${ARCH_OS_OPT_PACKAGE_LIST[@]}" --disable-download-timeout

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure Pacman & Reflector"
    # ----------------------------------------------------------------------------------------------------

    # Configure parrallel downloads, colors & multilib
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
    sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf
    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
    arch-chroot /mnt pacman -Syy --noconfirm

    # Configure reflector service
    {
        echo "# Reflector config for the systemd service"
        echo "--save /etc/pacman.d/mirrorlist"
        [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && echo "--country ${ARCH_OS_REFLECTOR_COUNTRY}"
        echo "--protocol https"
        echo "--latest 5"
        echo "--sort rate"
    } >/mnt/etc/xdg/reflector/reflector.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Generate /etc/fstab"
    # ----------------------------------------------------------------------------------------------------

    genfstab -U /mnt >>/mnt/etc/fstab

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create Swap"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_OS_SWAP_SIZE" != "0" ] && [ -n "$ARCH_OS_SWAP_SIZE" ]; then
        dd if=/dev/zero of=/mnt/swapfile bs=1G count="$ARCH_OS_SWAP_SIZE" status=progress
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile
        swapon /mnt/swapfile
        echo "# Swapfile" >>/mnt/etc/fstab
        echo "/swapfile none swap defaults 0 0" >>/mnt/etc/fstab
    else
        echo "> Skipped"
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Timezone & System Clock"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$ARCH_OS_TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc # Set hardware clock from system clock

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set Console Keymap"
    # ----------------------------------------------------------------------------------------------------

    echo "KEYMAP=$ARCH_OS_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf
    [ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=$ARCH_OS_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Generate Locale"
    # ----------------------------------------------------------------------------------------------------

    echo "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" >/mnt/etc/locale.conf
    for ((i = 0; i < ${#ARCH_OS_LOCALE_GEN_LIST[@]}; i++)); do sed -i "s/^#${ARCH_OS_LOCALE_GEN_LIST[$i]}/${ARCH_OS_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen"; done
    arch-chroot /mnt locale-gen

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set Hostname (${ARCH_OS_HOSTNAME})"
    # ----------------------------------------------------------------------------------------------------

    echo "$ARCH_OS_HOSTNAME" >/mnt/etc/hostname

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set /etc/hosts"
    # ----------------------------------------------------------------------------------------------------

    {
        echo '127.0.0.1    localhost'
        echo '::1          localhost'
    } >/mnt/etc/hosts

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set /etc/environment"
    # ----------------------------------------------------------------------------------------------------

    {
        echo 'EDITOR=nano'
        echo 'VISUAL=nano'
    } >/mnt/etc/environment

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create Initial Ramdisk"
    # ----------------------------------------------------------------------------------------------------

    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect modconf block sd-encrypt filesystems sd-vconsole fsck)/" /mnt/etc/mkinitcpio.conf
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect modconf block filesystems sd-vconsole fsck)/" /mnt/etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Bootloader (systemdboot)"
    # ----------------------------------------------------------------------------------------------------

    # Install systemdboot to /boot
    arch-chroot /mnt bootctl --esp-path=/boot install

    # Kernel args
    swap_device_uuid="$(findmnt -no UUID -T /mnt/swapfile)"
    swap_file_offset="$(filefrag -v /mnt/swapfile | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')"
    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        # Encryption enabled
        kernel_args="rd.luks.name=$(blkid -s UUID -o value "${ARCH_OS_ROOT_PARTITION}")=cryptroot root=/dev/mapper/cryptroot rw init=/usr/lib/systemd/systemd quiet splash vt.global_cursor_default=0 resume=/dev/mapper/cryptroot resume_offset=${swap_file_offset}"
    else
        # Encryption disabled
        kernel_args="root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_OS_ROOT_PARTITION}") rw init=/usr/lib/systemd/systemd quiet splash vt.global_cursor_default=0 resume=UUID=${swap_device_uuid} resume_offset=${swap_file_offset}"
    fi

    # Create Bootloader config
    {
        echo 'default arch.conf'
        echo 'console-mode auto'
        echo 'timeout 0'
        echo 'editor yes'
    } >/mnt/boot/loader/loader.conf

    # Create default boot entry
    {
        echo 'title   Arch Linux'
        echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
        [ -n "$ARCH_OS_MICROCODE" ] && echo "initrd  /${ARCH_OS_MICROCODE}.img"
        echo "initrd  /initramfs-${ARCH_OS_KERNEL}.img"
        echo "options ${kernel_args}"
    } >/mnt/boot/loader/entries/arch.conf

    # Create fallback boot entry
    {
        echo 'title   Arch Linux (Fallback)'
        echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
        [ -n "$ARCH_OS_MICROCODE" ] && echo "initrd  /${ARCH_OS_MICROCODE}.img"
        echo "initrd  /initramfs-${ARCH_OS_KERNEL}-fallback.img"
        echo "options ${kernel_args}"
    } >/mnt/boot/loader/entries/arch-fallback.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create User (${ARCH_OS_USERNAME})"
    # ----------------------------------------------------------------------------------------------------

    # Create new user
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"

    # Allow users in group wheel to use sudo
    sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers

    # Add password feedback
    echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers

    # Change passwords
    printf "%s\n%s" "${ARCH_OS_PASSWORD}" "${ARCH_OS_PASSWORD}" | arch-chroot /mnt passwd
    printf "%s\n%s" "${ARCH_OS_PASSWORD}" "${ARCH_OS_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_OS_USERNAME"

    # Add sudo needs no password rights (only for installation)
    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable Essential Services"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt systemctl enable NetworkManager              # Network Manager
    arch-chroot /mnt systemctl enable systemd-timesyncd.service   # Sync time from internet after boot
    arch-chroot /mnt systemctl enable reflector.service           # Rank mirrors after boot
    arch-chroot /mnt systemctl enable paccache.timer              # Discard cached/unused packages weekly
    arch-chroot /mnt systemctl enable pkgfile-update.timer        # Pkgfile update timer
    arch-chroot /mnt systemctl enable fstrim.timer                # SSD support
    arch-chroot /mnt systemctl enable systemd-boot-update.service # Auto bootloader update

    # Out of memory killer (swap is required)
    [ "$ARCH_OS_SWAP_SIZE" != "0" ] && [ -n "$ARCH_OS_SWAP_SIZE" ] && arch-chroot /mnt systemctl enable systemd-oomd.service

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure System"
    # ----------------------------------------------------------------------------------------------------

    # Reduce shutdown timeout
    sed -i "s/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf

    # Set Nano colors
    sed -i 's;^# include "/usr/share/nano/\*\.nanorc";include "/usr/share/nano/*.nanorc"\ninclude "/usr/share/nano/extra/*.nanorc";g' /mnt/etc/nanorc

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install AUR Helper"
    # ----------------------------------------------------------------------------------------------------

    # Install paru as user
    repo_url="https://aur.archlinux.org/paru-bin.git"
    tmp_name=$(mktemp -u "/home/${ARCH_OS_USERNAME}/paru-bin.XXXXXXXXXX")
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git clone "$repo_url" "$tmp_name"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "cd $tmp_name && makepkg -si --noconfirm"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- rm -rf "$tmp_name"

    # Paru config
    sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf
    sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Bootsplash"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout plymouth

        # Configure mkinitcpio
        sed -i "s/base systemd keyboard/base systemd plymouth keyboard/g" /mnt/etc/mkinitcpio.conf

        # Install plymouth theme
        repo_url="https://github.com/murkl/plymouth-theme-arch-os.git"
        tmp_name=$(mktemp -u "/home/${ARCH_OS_USERNAME}/plymouth-theme-arch-os.XXXXXXXXXX")
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git clone "$repo_url" "$tmp_name"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "cd ${tmp_name}/aur && makepkg -si --noconfirm"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- rm -rf "$tmp_name"

        # Set Theme & rebuild initram disk
        arch-chroot /mnt plymouth-set-default-theme -R arch-os
    else
        echo "> Skipped"
    fi

    # ----------------------------------------------------------------------------------------------------
    # START INSTALL GNOME
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_OS_GNOME_ENABLED" = "true" ]; then

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Install GNOME Packages (This may take a while ~ 15 min)"
        # ----------------------------------------------------------------------------------------------------

        # Install packages
        packages=()

        # GNOME base
        packages+=("gnome")                   # GNOME core
        packages+=("gnome-tweaks")            # GNOME tweaks
        packages+=("gnome-browser-connector") # GNOME Extensions browser connector
        packages+=("gnome-themes-extra")      # GNOME themes
        packages+=("gnome-firmware")          # GNOME firmware manager
        packages+=("power-profiles-daemon")   # GNOME power profiles support
        packages+=("fwupd")                   # GNOME security settings
        packages+=("rygel")                   # GNOME media sharing support
        packages+=("cups")                    # GNOME printer support

        # GNOME wayland screensharing, flatpak & pipewire support
        packages+=("xdg-desktop-portal")
        packages+=("xdg-desktop-portal-gtk")
        packages+=("xdg-desktop-portal-gnome")

        # GNOME legacy Indicator support (need for gnome extension) (51 packages)
        #packages+=("libappindicator-gtk2")
        #packages+=("libappindicator-gtk3")
        #packages+=("lib32-libappindicator-gtk2")
        #packages+=("lib32-libappindicator-gtk3")

        # Audio
        packages+=("pipewire")       # Pipewire
        packages+=("pipewire-alsa")  # Replacement for alsa
        packages+=("pipewire-pulse") # Replacement for pulse
        packages+=("pipewire-jack")  # Replacement for jack
        packages+=("wireplumber")    # Pipewire session manager
        #packages+=("lib32-pipewire")      # Pipewire 32 bit
        #packages+=("lib32-pipewire-jack") # Replacement for jack 32 bit

        # Networking & Access
        packages+=("samba") # Windows Network Share
        packages+=("gvfs")  # Need for Nautilus
        packages+=("gvfs-mtp")
        packages+=("gvfs-smb")
        packages+=("gvfs-nfs")
        packages+=("gvfs-afc")
        packages+=("gvfs-goa")
        packages+=("gvfs-gphoto2")
        packages+=("gvfs-google")

        # Utils (https://wiki.archlinux.org/title/File_systems)
        packages+=("nfs-utils")
        packages+=("f2fs-tools")
        packages+=("udftools")
        packages+=("dosfstools")
        packages+=("ntfs-3g")
        packages+=("exfat-utils")
        packages+=("p7zip")
        packages+=("zip")
        packages+=("unrar")
        packages+=("tar")

        # Codecs
        packages+=("gst-libav")
        packages+=("gst-plugin-pipewire")
        packages+=("gst-plugins-ugly")
        packages+=("libdvdcss")

        # Optimization
        #packages+=("gamemode")
        #packages+=("lib32-gamemode")

        # Driver
        #packages+=("xf86-input-synaptics") # For some touchpads

        # Fonts
        packages+=("noto-fonts")
        packages+=("noto-fonts-emoji")
        packages+=("ttf-liberation")
        packages+=("ttf-dejavu")

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

        # ----------------------------------------------------------------------------------------------------

        # VM Guest support (if VM detected)
        hypervisor=$(systemd-detect-virt)
        case $hypervisor in
        kvm)
            print_whiptail_info "KVM has been detected, setting up guest tools."
            arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout spice spice-vdagent spice-protocol spice-gtk
            arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout qemu-guest-agent
            arch-chroot /mnt systemctl enable qemu-guest-agent
            ;;
        vmware)
            print_whiptail_info "VMWare Workstation/ESXi has been detected, setting up guest tools."
            arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout open-vm-tools
            arch-chroot /mnt systemctl enable vmtoolsd
            arch-chroot /mnt systemctl enable vmware-vmblock-fuse
            ;;
        oracle)
            print_whiptail_info "VirtualBox has been detected, setting up guest tools."
            arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout virtualbox-guest-utils
            arch-chroot /mnt systemctl enable vboxservice
            ;;
        microsoft)
            arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeouts hyperv
            print_whiptail_info "Hyper-V has been detected, setting up guest tools."
            arch-chroot /mnt systemctl enable hv_fcopy_daemon
            arch-chroot /mnt systemctl enable hv_kvp_daemon
            arch-chroot /mnt systemctl enable hv_vss_daemon
            ;;
        none)
            print_whiptail_info "No VM detected"
            # Do nothing
            ;;
        esac

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Remove packages"
        # ----------------------------------------------------------------------------------------------------

        # Init package list
        packages=()

        # Check & add to package list
        arch-chroot /mnt pacman -Q --info gnome-maps &>/dev/null && packages+=("gnome-maps")
        arch-chroot /mnt pacman -Q --info gnome-music &>/dev/null && packages+=("gnome-music")
        arch-chroot /mnt pacman -Q --info gnome-photos &>/dev/null && packages+=("gnome-photos")
        arch-chroot /mnt pacman -Q --info gnome-contacts &>/dev/null && packages+=("gnome-contacts")
        arch-chroot /mnt pacman -Q --info gnome-connections &>/dev/null && packages+=("gnome-connections")
        arch-chroot /mnt pacman -Q --info cheese &>/dev/null && packages+=("cheese")
        arch-chroot /mnt pacman -Q --info snapshot &>/dev/null && packages+=("snapshot")

        # Remove packages from list
        arch-chroot /mnt pacman -Rsn --noconfirm "${packages[@]}"

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Enable GNOME Auto Login"
        # ----------------------------------------------------------------------------------------------------

        grep -qrnw /mnt/etc/gdm/custom.conf -e "AutomaticLoginEnable" || sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${ARCH_OS_USERNAME}\n\n\[security\]/g" /mnt/etc/gdm/custom.conf

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Configure Git"
        # ----------------------------------------------------------------------------------------------------

        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- mkdir -p "/home/${ARCH_OS_USERNAME}/.config/git"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- touch "/home/${ARCH_OS_USERNAME}/.config/git/config"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git config --global credential.helper /usr/lib/git-core/git-credential-libsecret

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Configure Samba"
        # ----------------------------------------------------------------------------------------------------

        mkdir -p "/mnt/etc/samba/"
        {
            echo "[global]"
            echo "   workgroup = WORKGROUP"
            echo "   log file = /var/log/samba/%m"
        } >/mnt/etc/samba/smb.conf

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Set X11 Keyboard Layout"
        # ----------------------------------------------------------------------------------------------------

        {
            echo 'Section "InputClass"'
            echo '    Identifier "keyboard"'
            echo '    MatchIsKeyboard "yes"'
            echo '    Option "XkbLayout" "'"${ARCH_OS_X11_KEYBOARD_LAYOUT}"'"'
            echo '    Option "XkbModel" "pc105"'
            echo '    Option "XkbVariant" "'"${ARCH_OS_X11_KEYBOARD_VARIANT}"'"'
            echo 'EndSection'
        } >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Enable GNOME Services"
        # ----------------------------------------------------------------------------------------------------

        arch-chroot /mnt systemctl enable gdm.service                                                              # GNOME
        arch-chroot /mnt systemctl enable bluetooth.service                                                        # Bluetooth
        arch-chroot /mnt systemctl enable avahi-daemon                                                             # Network browsing service
        arch-chroot /mnt systemctl enable cups.service                                                             # Printer
        arch-chroot /mnt systemctl enable smb.service                                                              # Samba
        arch-chroot /mnt systemctl enable nmb.service                                                              # Samba
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire.service       # Pipewire
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire-pulse.service # Pipewire
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user wireplumber.service    # Pipewire

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Hide Applications Icons"
        # ----------------------------------------------------------------------------------------------------

        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- mkdir -p "/home/$ARCH_OS_USERNAME/.local/share/applications"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/avahi-discover.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/bssh.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/bvnc.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/qv4l2.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/qvidcap.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/lstopo.desktop"

    else
        # Skip Gnome progresses
        PROGRESS_COUNT=33
    fi

    # ----------------------------------------------------------------------------------------------------
    # END INSTALL GNOME
    # ----------------------------------------------------------------------------------------------------

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Cleanup Installation"
    # ----------------------------------------------------------------------------------------------------

    # Copy installer.conf to users home dir
    cp "$INSTALLER_CONFIG" "/mnt/home/${ARCH_OS_USERNAME}/installer.conf"

    # Remove sudo needs no password rights
    sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # Set home permission
    arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"

    # Remove orphans and force return true
    # shellcheck disable=SC2016
    arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Rns --noconfirm $(pacman -Qtdq) || true'

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Arch Installation finished"
    # ----------------------------------------------------------------------------------------------------

) | whiptail --title "$TITLE" --gauge "Start Arch Installation..." 7 "$TUI_WIDTH" 0

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////// INSTALLATION FINISHED ///////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Goto exit trap (see above)
exit 0
