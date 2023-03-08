#!/usr/bin/env bash
# shellcheck disable=SC1090

# /////////////////////////////////////////////////////
# ARCH INSTALL CONFIG
# /////////////////////////////////////////////////////

ARCH_INSTALL_CONFIG="/tmp/arch-install.conf"

# /////////////////////////////////////////////////////
# VARIABLES
# /////////////////////////////////////////////////////

WORKING_DIR="$(cd "$(dirname "$0")" &>/dev/null && pwd)"

# /////////////////////////////////////////////////////
# DESKTOP ENVIRONMENTS
# /////////////////////////////////////////////////////

ENVIRONMENT_DIR="${WORKING_DIR}/../environment"
ENVIRONMENT_LIST=()
ENVIRONMENT_LIST+=("gnome") && ENVIRONMENT_LIST+=("GNOME Desktop")

# /////////////////////////////////////////////////////
# TUI
# /////////////////////////////////////////////////////

TUI_TITLE="Arch Linux Setup"
TUI_WIDTH="80"
TUI_HEIGHT="20"
TUI_POSITION=""

# /////////////////////////////////////////////////////
# PRINT FUNCTIONS
# /////////////////////////////////////////////////////

print_config_menu_entry() {
    local key="$1"
    local val="$2" && val=$(echo "$val" | xargs)
    for ((i = ${#key}; i < 12; i++)); do local spaces="${spaces} "; done
    [ -z "$val" ] && val='?'
    echo "${key} ${spaces} ->  $val"
}

# /////////////////////////////////////////////////////
# CONFIG FILE HELPER
# /////////////////////////////////////////////////////

set_config_entry() {
    local config_key="$1"
    local config_value="$2"
    # Check if config entry already exists (add or replace value)
    grep -qrnw "$ARCH_INSTALL_CONFIG" -e "^${config_key}=.*" &>/dev/null && sed -i "s;^${config_key}=.*;${config_key}=\"${config_value}\";g" "$ARCH_INSTALL_CONFIG" || echo "$config_key=\"$config_value\"" >>"$ARCH_INSTALL_CONFIG"
}

set_config_array() {
    local config_key="$1" && shift
    local config_value_array=("$@")
    # Create string with apostrophe and remove trailing space
    local array_value && array_value=$(printf '"%s" ' "${config_value_array[@]}" | sed 's/.$//')
    # Check if config entry already exists (add or replace value)
    grep -qrnw "$ARCH_INSTALL_CONFIG" -e "^${config_key}=.*" &>/dev/null && sed -i "s;^${config_key}=.*;${config_key}=($array_value);g" "$ARCH_INSTALL_CONFIG" || echo "$config_key=($array_value)" >>"$ARCH_INSTALL_CONFIG"
}

# /////////////////////////////////////////////////////
# LOAD CONFIG & CHECK STATE
# /////////////////////////////////////////////////////

load_config_and_check_state() {

    local show_promt="false" && [ "$1" = "show_promt" ] && show_promt="true"

    # Unset all installation variables (set only from config file)
    unset ARCH_USERNAME
    unset ARCH_HOSTNAME
    unset ARCH_PASSWORD
    unset ARCH_DISK
    unset ARCH_BOOT_PARTITION
    unset ARCH_ROOT_PARTITION
    unset ARCH_ENCRYPTION_ENABLED
    unset ARCH_FSTRIM_ENABLED
    unset ARCH_SWAP_SIZE
    unset ARCH_MICROCODE
    unset ARCH_LANGUAGE
    unset ARCH_TIMEZONE
    unset ARCH_LOCALE_LANG
    unset ARCH_LOCALE_GEN_LIST
    unset ARCH_VCONSOLE_KEYMAP
    unset ARCH_VCONSOLE_FONT
    unset ARCH_MULTILIB_ENABLED
    unset ARCH_AUR_ENABLED
    unset ARCH_DOCKER_ENABLED
    unset ARCH_PKGFILE_ENABLED
    unset ARCH_WATCHDOG_ENABLED
    unset ARCH_SHUTDOWN_TIMEOUT_SEC
    unset ENVIRONMENT_X11_KEYBOARD_LAYOUT
    unset ENVIRONMENT_X11_KEYBOARD_VARIANT
    unset ENVIRONMENT_DESKTOP
    unset ENVIRONMENT_DRIVER

    # Load config if exists
    [ -f "$ARCH_INSTALL_CONFIG" ] && source "$ARCH_INSTALL_CONFIG"

    # Check multiple language config
    if [ -z "$ARCH_LANGUAGE" ] || [ -z "$ARCH_TIMEZONE" ] || [ -z "$ARCH_LOCALE_LANG" ] || [ -z "${ARCH_LOCALE_GEN_LIST[*]}" ] || [ -z "$ARCH_VCONSOLE_KEYMAP" ] || [ -z "$ARCH_VCONSOLE_FONT" ] || [ -z "$ENVIRONMENT_X11_KEYBOARD_LAYOUT" ] || [ -z "$ENVIRONMENT_X11_KEYBOARD_VARIANT" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Language config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_LANGUAGE" && set_config_entry "ARCH_TIMEZONE" && set_config_entry "ARCH_LOCALE_LANG" && set_config_array "ARCH_LOCALE_GEN_LIST" && set_config_entry "ARCH_VCONSOLE_KEYMAP" && set_config_entry "ARCH_VCONSOLE_FONT" && set_config_entry "ENVIRONMENT_X11_KEYBOARD_LAYOUT" && set_config_entry "ENVIRONMENT_X11_KEYBOARD_VARIANT"
        TUI_POSITION="language"
        return 1
    fi

    # Check Hostname
    if [ -z "$ARCH_HOSTNAME" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Hostname config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_HOSTNAME"
        TUI_POSITION="hostname"
        return 1
    fi

    # Check User
    if [ -z "$ARCH_USERNAME" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "User config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_USERNAME"
        TUI_POSITION="user"
        return 1
    fi

    # Check Password
    if [ -z "$ARCH_PASSWORD" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Password config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_PASSWORD"
        TUI_POSITION="password"
        return 1
    fi

    # Check multiple disk config
    if [ -z "$ARCH_DISK" ] || [ -z "$ARCH_BOOT_PARTITION" ] || [ -z "$ARCH_ROOT_PARTITION" ] || [ -z "$ARCH_FSTRIM_ENABLED" ] || [ -z "$ARCH_ENCRYPTION_ENABLED" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Disk config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_DISK" && set_config_entry "ARCH_BOOT_PARTITION" && set_config_entry "ARCH_ROOT_PARTITION" && set_config_entry "ARCH_FSTRIM_ENABLED" && set_config_entry "ARCH_ENCRYPTION_ENABLED"
        TUI_POSITION="disk"
        return 1
    fi

    # Check Swap
    if [ -z "$ARCH_SWAP_SIZE" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Swap config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_SWAP_SIZE"
        TUI_POSITION="swap"
        return 1
    fi

    # Check Microcode
    if [ -z "$ARCH_MICROCODE" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Microcode config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_MICROCODE"
        TUI_POSITION="microcode"
        return 1
    fi

    # Check MultiLib
    if [ -z "$ARCH_MULTILIB_ENABLED" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "MultiLib config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_MULTILIB_ENABLED"
        TUI_POSITION="multilib"
        return 1
    fi

    # Check AUR
    if [ -z "$ARCH_AUR_ENABLED" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "AUR config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_AUR_ENABLED"
        TUI_POSITION="aur"
        return 1
    fi

    # Check Docker
    if [ -z "$ARCH_DOCKER_ENABLED" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Docker config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ARCH_DOCKER_ENABLED"
        TUI_POSITION="docker"
        return 1
    fi

    # Check Environment
    if [ -z "$ENVIRONMENT_DESKTOP" ] || [ -z "$ENVIRONMENT_DRIVER" ]; then
        [ "$show_promt" = "true" ] && whiptail --title "$TUI_TITLE" --msgbox "Environment config is missing" "$TUI_HEIGHT" "$TUI_WIDTH"
        set_config_entry "ENVIRONMENT_DESKTOP" && set_config_entry "ENVIRONMENT_DRIVER"
        TUI_POSITION="environment"
        return 1
    fi

    # Check & set defaults
    if [ -z "$ARCH_PKGFILE_ENABLED" ] || [ -z "$ARCH_WATCHDOG_ENABLED" ] || [ -z "$ARCH_SHUTDOWN_TIMEOUT_SEC" ]; then
        set_config_entry "ARCH_PKGFILE_ENABLED" "true"
        set_config_entry "ARCH_WATCHDOG_ENABLED" "false"
        set_config_entry "ARCH_SHUTDOWN_TIMEOUT_SEC" "5s"
    fi

    # Jump to install
    TUI_POSITION="install"
}

# /////////////////////////////////////////////////////
# OPEN CONFIG MENU & SET PROPERTY
# /////////////////////////////////////////////////////

open_config_menu_and_set_property() {

    case "${1}" in

    "language")
        language=$(whiptail --title "$TUI_TITLE" --menu "\nChoose Setup Language" --nocancel --notags "$TUI_HEIGHT" "$TUI_WIDTH" 2 "english" "English" "german" "German" 3>&1 1>&2 2>&3)
        if [ "$language" = "english" ]; then
            set_config_entry "ARCH_LANGUAGE" "english"
            set_config_entry "ARCH_TIMEZONE" "Europe/Berlin"
            set_config_entry "ARCH_LOCALE_LANG" "en_US.UTF-8"
            set_config_array "ARCH_LOCALE_GEN_LIST" "en_US.UTF-8" "UTF-8"
            set_config_entry "ARCH_VCONSOLE_KEYMAP" "en-latin1-nodeadkeys"
            set_config_entry "ARCH_VCONSOLE_FONT" "eurlatgr"
            set_config_entry "ENVIRONMENT_X11_KEYBOARD_LAYOUT" "en"
            set_config_entry "ENVIRONMENT_X11_KEYBOARD_VARIANT" "nodeadkeys"
        fi
        if [ "$language" = "german" ]; then
            set_config_entry "ARCH_LANGUAGE" "german"
            set_config_entry "ARCH_TIMEZONE" "Europe/Berlin"
            set_config_entry "ARCH_LOCALE_LANG" "de_DE.UTF-8"
            set_config_array "ARCH_LOCALE_GEN_LIST" "de_DE.UTF-8 UTF-8" "de_DE ISO-8859-1" "de_DE@euro ISO-8859-15" "en_US.UTF-8 UTF-8"
            set_config_entry "ARCH_VCONSOLE_KEYMAP" "de-latin1-nodeadkeys"
            set_config_entry "ARCH_VCONSOLE_FONT" "eurlatgr"
            set_config_entry "ENVIRONMENT_X11_KEYBOARD_LAYOUT" "de"
            set_config_entry "ENVIRONMENT_X11_KEYBOARD_VARIANT" "nodeadkeys"
        fi
        ;;

    "hostname")
        hostname=$(whiptail --title "$TUI_TITLE" --inputbox "\nEnter Hostname" "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_HOSTNAME" 3>&1 1>&2 2>&3) || return 1
        if [ -z "$hostname" ]; then
            set_config_entry "ARCH_HOSTNAME"
            whiptail --title "$TUI_TITLE" --msgbox "Error: Hostname is null" "$TUI_HEIGHT" "$TUI_WIDTH"
            return 1
        fi
        set_config_entry "ARCH_HOSTNAME" "$hostname"
        ;;

    "user")
        username=$(whiptail --title "$TUI_TITLE" --inputbox "\nEnter Username" "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_USERNAME" 3>&1 1>&2 2>&3) || return 1
        if [ -z "$username" ]; then
            set_config_entry "ARCH_USERNAME"
            whiptail --title "$TUI_TITLE" --msgbox "Error: Username is null" "$TUI_HEIGHT" "$TUI_WIDTH"
            return 1
        fi
        set_config_entry "ARCH_USERNAME" "$username"
        ;;

    "password")
        password=$(whiptail --title "$TUI_TITLE" --passwordbox "\nEnter Password" "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3) || return 1
        if [ -z "$password" ]; then
            set_config_entry "ARCH_PASSWORD"
            whiptail --title "$TUI_TITLE" --msgbox "Error: Password is null" "$TUI_HEIGHT" "$TUI_WIDTH"
            return 1
        fi
        password_check=$(whiptail --title "$TUI_TITLE" --passwordbox "\nEnter Password (again)" "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3) || return 1
        if [ "$password" != "$password_check" ]; then
            set_config_entry "ARCH_PASSWORD"
            whiptail --title "$TUI_TITLE" --msgbox "Error: Password not identical" "$TUI_HEIGHT" "$TUI_WIDTH"
            return 1
        fi
        set_config_entry "ARCH_PASSWORD" "$password"
        ;;

    "disk")
        disk_array=()
        while read -r disk_line; do
            disk_array+=("/dev/$disk_line")
            disk_array+=(" ($(lsblk -d -n -o SIZE /dev/"$disk_line"))")
        done < <(lsblk -I 8,259,254 -d -o KNAME -n)

        # Check disk found
        if [ "${#disk_array[@]}" = "0" ]; then
            whiptail --title "$TUI_TITLE" --msgbox "No Disk found" "$TUI_HEIGHT" "$TUI_WIDTH"
            return 1
        fi

        # Select Disk
        disk=$(whiptail --title "$TUI_TITLE" --menu "\nChoose Installation Disk" "$TUI_HEIGHT" "$TUI_WIDTH" "${#disk_array[@]}" "${disk_array[@]}" 3>&1 1>&2 2>&3) || return 1
        [[ "$disk" = "/dev/nvm"* ]] && boot_partition="${disk}p1" || boot_partition="${disk}1"
        [[ "$disk" = "/dev/nvm"* ]] && root_partition="${disk}p2" || root_partition="${disk}2"

        # Fstrim
        ssd_enabled="false" && whiptail --title "$TUI_TITLE" --yesno "Enable SSD Support?" "$TUI_HEIGHT" "$TUI_WIDTH" && ssd_enabled="true"

        # Disk Encryption
        encryption_enabled="false" && whiptail --title "$TUI_TITLE" --yesno "Enable Disk Encryption?" "$TUI_HEIGHT" "$TUI_WIDTH" && encryption_enabled="true"

        set_config_entry "ARCH_DISK" "$disk"
        set_config_entry "ARCH_BOOT_PARTITION" "$boot_partition"
        set_config_entry "ARCH_ROOT_PARTITION" "$root_partition"
        set_config_entry "ARCH_ENCRYPTION_ENABLED" "$encryption_enabled"
        set_config_entry "ARCH_FSTRIM_ENABLED" "$ssd_enabled"
        ;;

    "swap")
        swap_size="$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 + 1))"
        swap_size=$(whiptail --title "$TUI_TITLE" --inputbox "\nEnter Swap Size in GB (0 = disable)" "$TUI_HEIGHT" "$TUI_WIDTH" "$swap_size" 3>&1 1>&2 2>&3) || return 1
        if [ -z "$swap_size" ]; then
            set_config_entry "ARCH_SWAP_SIZE"
            whiptail --title "$TUI_TITLE" --msgbox "Error: Swap is null" "$TUI_HEIGHT" "$TUI_WIDTH"
            return 1
        fi
        set_config_entry "ARCH_SWAP_SIZE" "$swap_size"
        ;;

    "microcode")
        microcode=$(whiptail --title "$TUI_TITLE" --menu "\nSelect Microcode" --nocancel --notags "$TUI_HEIGHT" "$TUI_WIDTH" 3 "none" "None" "intel-ucode" "Intel" "amd-ucode" "AMD" 3>&1 1>&2 2>&3)
        set_config_entry "ARCH_MICROCODE" "$microcode"
        ;;

    "multilib")
        multilib_enabled="false" && whiptail --title "$TUI_TITLE" --yesno "Enable MultiLib (32 Bit Support)?" "$TUI_HEIGHT" "$TUI_WIDTH" && multilib_enabled="true"
        set_config_entry "ARCH_MULTILIB_ENABLED" "$multilib_enabled"
        ;;

    "aur")
        aur_enabled="false" && whiptail --title "$TUI_TITLE" --yesno "Enable Paru AUR Helper?" "$TUI_HEIGHT" "$TUI_WIDTH" && aur_enabled="true"
        set_config_entry "ARCH_AUR_ENABLED" "$aur_enabled"
        ;;

    "docker")
        docker_enabled="false" && whiptail --title "$TUI_TITLE" --yesno "Enable Docker?" "$TUI_HEIGHT" "$TUI_WIDTH" && docker_enabled="true"
        set_config_entry "ARCH_DOCKER_ENABLED" "$docker_enabled"
        ;;

    "environment")
        environment=$(whiptail --title "$TUI_TITLE" --menu "\nSelect Environment" --nocancel --notags "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#ENVIRONMENT_LIST[@]} / 2 + 1) + (${#ENVIRONMENT_LIST[@]} % 2)))" "none" "None" "${ENVIRONMENT_LIST[@]}" 3>&1 1>&2 2>&3)
        if [ "$environment" = "none" ]; then
            set_config_entry "ENVIRONMENT_DESKTOP" "none"
            set_config_entry "ENVIRONMENT_DRIVER" "none"
        else
            [ ! -f "${ENVIRONMENT_DIR}/${environment}.sh" ] && echo "ERROR: '${ENVIRONMENT_DIR}/${environment}.sh' not found" && exit 1
            mapfile -t desktop_graphics_driver_list <<<"$(bash -c "${ENVIRONMENT_DIR}/${environment}.sh --list-driver")" || exit 1
            driver=$(whiptail --title "$TUI_TITLE" --menu "\nSelect Driver" --nocancel --notags "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#desktop_graphics_driver_list[@]} / 2 + 1) + (${#desktop_graphics_driver_list[@]} % 2)))" "none" "None" "${desktop_graphics_driver_list[@]}" 3>&1 1>&2 2>&3)
            set_config_entry "ENVIRONMENT_DESKTOP" "$environment"
            set_config_entry "ENVIRONMENT_DRIVER" "$driver"
        fi
        ;;

    *)
        echo "ERROR: Menu config entry ${1} not found" && exit 1
        ;;

    esac
}

# /////////////////////////////////////////////////////
# START SCRIPT
# /////////////////////////////////////////////////////

# Check UEFI support
[ ! -d /sys/firmware/efi ] && echo "ERROR: BIOS not supported" && exit 1

# Open TUI menu
while (true); do

    # Clear screen & check config state
    clear && load_config_and_check_state

    # Create TUI menu entries
    menu_entry_array=()
    menu_entry_array+=("language") && menu_entry_array+=("$(print_config_menu_entry "Language" "${ARCH_LANGUAGE}")")
    menu_entry_array+=("hostname") && menu_entry_array+=("$(print_config_menu_entry "Hostname" "${ARCH_HOSTNAME}")")
    menu_entry_array+=("user") && menu_entry_array+=("$(print_config_menu_entry "User" "${ARCH_USERNAME}")")
    menu_entry_array+=("password") && menu_entry_array+=("$(print_config_menu_entry "Password" "$([ -n "$ARCH_PASSWORD" ] && echo "******")")")
    menu_entry_array+=("disk") && menu_entry_array+=("$(print_config_menu_entry "Disk" "${ARCH_DISK}$([ "$ARCH_FSTRIM_ENABLED" = "true" ] && echo ", ssd")$([ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && echo ", encrypted")")")
    menu_entry_array+=("swap") && menu_entry_array+=("$(print_config_menu_entry "Swap" "$([ -n "$ARCH_SWAP_SIZE" ] && { [ "$ARCH_SWAP_SIZE" != "0" ] && echo "${ARCH_SWAP_SIZE} GB" || echo "disabled"; })")")
    menu_entry_array+=("microcode") && menu_entry_array+=("$(print_config_menu_entry "Microcode" "${ARCH_MICROCODE}")")
    menu_entry_array+=("multilib") && menu_entry_array+=("$(print_config_menu_entry "MultiLib" "${ARCH_MULTILIB_ENABLED}")")
    menu_entry_array+=("aur") && menu_entry_array+=("$(print_config_menu_entry "AUR" "${ARCH_AUR_ENABLED}")")
    menu_entry_array+=("docker") && menu_entry_array+=("$(print_config_menu_entry "Docker" "${ARCH_DOCKER_ENABLED}")")
    menu_entry_array+=("environment") && menu_entry_array+=("$(print_config_menu_entry "Environment" "${ENVIRONMENT_DESKTOP}$([ -n "${ENVIRONMENT_DRIVER}" ] && [ "${ENVIRONMENT_DRIVER}" != 'none' ] && echo ", ${ENVIRONMENT_DRIVER}")")")
    menu_entry_array+=("space") && menu_entry_array+=("")
    menu_entry_array+=("install") && menu_entry_array+=("> Start Installation")

    # Open TUI menu
    menu_selection=$(whiptail --title "$TUI_TITLE" --menu "\n" --ok-button "Ok" --cancel-button "Exit" --notags --default-item "$TUI_POSITION" "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#menu_entry_array[@]} / 2) + (${#menu_entry_array[@]} % 2)))" "${menu_entry_array[@]}" 3>&1 1>&2 2>&3) || exit

    case "${menu_selection}" in

    "install")

        # Check config
        load_config_and_check_state "show_promt" || continue

        # Show config and edit function
        if whiptail --title "Arch Setup Configuration" --yesno "$(cat "$ARCH_INSTALL_CONFIG")" --scrolltext --yes-button "Edit" --no-button "Continue" 30 90; then

            # Open config editor
            nano "$ARCH_INSTALL_CONFIG" </dev/tty || exit 1

            # Check and load config again
            load_config_and_check_state "show_promt" || continue
        fi

        # Start installation
        whiptail --title "$TUI_TITLE" --yesno "Start Arch Linux Installation?\n\nAll data on ${ARCH_DISK} will be DELETED. This cannot be UNDONE!" "$TUI_HEIGHT" "$TUI_WIDTH" || continue

        # Clear TUI screen
        clear

        # Add scripts in the right order to script args
        script_args="" && [ "$ENVIRONMENT_DESKTOP" != "none" ] && script_args="${script_args} -s ${ENVIRONMENT_DIR}/${ENVIRONMENT_DESKTOP}.sh"

        # Execute arch-install.sh
        bash -c "${WORKING_DIR}/../arch-install.sh -f -c ${ARCH_INSTALL_CONFIG} ${script_args}" || exit 1
        exit $?
        ;;

    *)
        # Open config menu and set property
        open_config_menu_and_set_property "$menu_selection" || continue
        ;;

    esac
done
