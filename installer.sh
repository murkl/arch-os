#!/usr/bin/env bash
set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -u          # Uninitialized variables trigger errors
set -e          # Terminate if any command exits with a non-zero
set -E          # ERR trap inherited by shell functions (errtrace)
clear           # Clear

# ----------------------------------------------------------------------------------------------------
# SCRIPT VARIABLES
# ----------------------------------------------------------------------------------------------------

# Version
VERSION='1.2.1'

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

# Whiptail total processes begins by 0 (number of occurrences of print_whiptail_info - 3)
PROGRESS_TOTAL=40

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
ARCH_OS_REFLECTOR_COUNTRY=""
ARCH_OS_TIMEZONE=""
ARCH_OS_LOCALE_LANG=""
ARCH_OS_LOCALE_GEN_LIST=()
ARCH_OS_VCONSOLE_KEYMAP=""
ARCH_OS_VCONSOLE_FONT=""
ARCH_OS_X11_KEYBOARD_LAYOUT=""
ARCH_OS_X11_KEYBOARD_VARIANT=""
ARCH_OS_BOOTSPLASH_ENABLED=""
ARCH_OS_VARIANT=""
ARCH_OS_GRAPHICS_DRIVER=""
ARCH_OS_KERNEL=""
ARCH_OS_MICROCODE=""
ARCH_OS_VM_SUPPORT_ENABLED=""
ARCH_OS_SHELL_ENHANCED_ENABLED=""
ARCH_OS_AUR_HELPER=""
ARCH_OS_MULTILIB_ENABLED=""
ARCH_OS_ECN_ENABLED=""

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
    local key="$1" && shift
    local val="$1" && shift
    val=$(echo "$val" | xargs) # Trim spaces

    # If another arg is null, set val=null
    for arg in "${@}"; do [ -z "$arg" ] && val=""; done

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

default_config() {
    # Set default values (if not already set)
    [ -z "$ARCH_OS_HOSTNAME" ] && ARCH_OS_HOSTNAME="arch-os"
    [ -z "$ARCH_OS_KERNEL" ] && ARCH_OS_KERNEL="linux-zen"
    [ -z "$ARCH_OS_VM_SUPPORT_ENABLED" ] && ARCH_OS_VM_SUPPORT_ENABLED="true"
    [ -z "$ARCH_OS_SHELL_ENHANCED_ENABLED" ] && ARCH_OS_SHELL_ENHANCED_ENABLED="true"
    [ -z "$ARCH_OS_AUR_HELPER" ] && ARCH_OS_AUR_HELPER="paru"
    [ -z "$ARCH_OS_MULTILIB_ENABLED" ] && ARCH_OS_MULTILIB_ENABLED="true"
    [ -z "$ARCH_OS_ECN_ENABLED" ] && ARCH_OS_ECN_ENABLED="true"
    #[ -z "$ARCH_OS_VCONSOLE_FONT" ] && ARCH_OS_VCONSOLE_FONT="eurlatgr"
    #[ -z "$ARCH_OS_REFLECTOR_COUNTRY" ] && ARCH_OS_REFLECTOR_COUNTRY="Germany,France"
}

check_config() {
    default_config
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
    [ -z "${ARCH_OS_BOOTSPLASH_ENABLED}" ] && TUI_POSITION="bootsplash" && return 1
    [ -z "${ARCH_OS_VARIANT}" ] && TUI_POSITION="variant" && return 1
    [ "${ARCH_OS_VARIANT}" = "desktop" ] && [ -z "${ARCH_OS_GRAPHICS_DRIVER}" ] && TUI_POSITION="variant" && return 1
    [ "${ARCH_OS_VARIANT}" = "desktop" ] && [ -z "${ARCH_OS_X11_KEYBOARD_LAYOUT}" ] && TUI_POSITION="variant" && return 1
    # Success
    TUI_POSITION="install"
    return 0
}

create_config() {
    {
        echo "# ${TITLE} (generated: $(date --utc '+%Y-%m-%d %H:%M') UTC)"
        echo ""
        echo "# Hostname (core)"
        echo "ARCH_OS_HOSTNAME='${ARCH_OS_HOSTNAME}'"
        echo ""
        echo "# User (core)"
        echo "ARCH_OS_USERNAME='${ARCH_OS_USERNAME}'"
        echo ""
        echo "# Disk (core)"
        echo "ARCH_OS_DISK='${ARCH_OS_DISK}'"
        echo ""
        echo "# Boot partition (core)"
        echo "ARCH_OS_BOOT_PARTITION='${ARCH_OS_BOOT_PARTITION}'"
        echo ""
        echo "# Root partition (core)"
        echo "ARCH_OS_ROOT_PARTITION='${ARCH_OS_ROOT_PARTITION}'"
        echo ""
        echo "# Disk encryption (core) | Disable: false"
        echo "ARCH_OS_ENCRYPTION_ENABLED='${ARCH_OS_ENCRYPTION_ENABLED}'"
        echo ""
        echo "# Timezone (core) | Show available: ls /usr/share/zoneinfo/** | Example: Europe/Berlin"
        echo "ARCH_OS_TIMEZONE='${ARCH_OS_TIMEZONE}'"
        echo ""
        echo "# Locale (core) | Show available: ls /usr/share/i18n/locales | Example: de_DE"
        echo "ARCH_OS_LOCALE_LANG='${ARCH_OS_LOCALE_LANG}'"
        echo ""
        echo "# Locale List (core) | Show available: cat /etc/locale.gen"
        echo "ARCH_OS_LOCALE_GEN_LIST=(${ARCH_OS_LOCALE_GEN_LIST[*]@Q})"
        echo ""
        echo "# Console keymap (core) | Show available: localectl list-keymaps | Example: de-latin1-nodeadkeys"
        echo "ARCH_OS_VCONSOLE_KEYMAP='${ARCH_OS_VCONSOLE_KEYMAP}'"
        echo ""
        echo "# Console font (core) | Show available: find /usr/share/kbd/consolefonts/*.psfu.gz | Default: null | Example: eurlatgr"
        echo "ARCH_OS_VCONSOLE_FONT='${ARCH_OS_VCONSOLE_FONT}'"
        echo ""
        echo "# Kernel (core) | Default: linux-zen | Recommended: linux, linux-lts linux-zen, linux-hardened"
        echo "ARCH_OS_KERNEL='${ARCH_OS_KERNEL}'"
        echo ""
        echo "# Disable ECN support for legacy routers (core) | Default: true | Disable: false"
        echo "ARCH_OS_ECN_ENABLED='${ARCH_OS_ECN_ENABLED}'"
        echo ""
        echo "# Bootsplash (optional) | Disable: false"
        echo "ARCH_OS_BOOTSPLASH_ENABLED='${ARCH_OS_BOOTSPLASH_ENABLED}'"
        echo ""
        echo "# Arch OS Variant (mandatory) | Available: core, base, desktop"
        echo "ARCH_OS_VARIANT='${ARCH_OS_VARIANT}'"
        echo ""
        echo "# Shell Enhancement (base) | Default: true | Disable: false"
        echo "ARCH_OS_SHELL_ENHANCED_ENABLED='${ARCH_OS_SHELL_ENHANCED_ENABLED}'"
        echo ""
        echo "# AUR Helper (base) | Default: paru | Disable: none | Recommended: paru, yay, trizen, pikaur"
        echo "ARCH_OS_AUR_HELPER='${ARCH_OS_AUR_HELPER}'"
        echo ""
        echo "# MultiLib 32 Bit Support (base) | Default: true | Disable: false"
        echo "ARCH_OS_MULTILIB_ENABLED='${ARCH_OS_MULTILIB_ENABLED}'"
        echo ""
        echo "# Country used by reflector (base) | Default: null | Example: Germany,France"
        echo "ARCH_OS_REFLECTOR_COUNTRY='${ARCH_OS_REFLECTOR_COUNTRY}'"
        echo ""
        echo "# Driver (desktop) | Default: mesa | Available: mesa, intel_i915, nvidia, amd, ati"
        echo "ARCH_OS_GRAPHICS_DRIVER='${ARCH_OS_GRAPHICS_DRIVER}'"
        echo ""
        echo "# X11 keyboard layout (desktop) | Show available: localectl list-x11-keymap-layouts | Example: de"
        echo "ARCH_OS_X11_KEYBOARD_LAYOUT='${ARCH_OS_X11_KEYBOARD_LAYOUT}'"
        echo ""
        echo "# X11 keyboard variant (desktop) | Show available: localectl list-x11-keymap-variants | Default: null | Example: nodeadkeys"
        echo "ARCH_OS_X11_KEYBOARD_VARIANT='${ARCH_OS_X11_KEYBOARD_VARIANT}'"
        echo ""
        echo "# VM Support (desktop) | Default: true | Disable: false"
        echo "ARCH_OS_VM_SUPPORT_ENABLED='${ARCH_OS_VM_SUPPORT_ENABLED}'"
    } >"$INSTALLER_CONFIG"
}

# ----------------------------------------------------------------------------------------------------
# SETUP FUNCTIONS
# ----------------------------------------------------------------------------------------------------

tui_set_language() {

    # Loading
    clear && echo "Loading..."

    # Set timezone
    local user_input="$ARCH_OS_TIMEZONE"
    [ -z "$user_input" ] && user_input="$(curl -s http://ip-api.com/line?fields=timezone)"
    local desc='Enter "?" to select from menu'
    clear && user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nSet Timezone (auto detected)\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

    # If user timezone input is null
    if [ -z "$user_input" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Timezone is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_TIMEZONE=""
        create_config
        return 1
    fi

    # Check if user want select timezone from menu
    if [ "$user_input" = "?" ]; then
        items=$(/usr/bin/ls -l /usr/share/zoneinfo/ | grep '^d' | grep -v "right" | grep -v "posix" | gawk -F':[0-9]* ' '/:/{print $2}')
        options=() && for item in ${items}; do options+=("${item}" ""); done
        timezone=$(whiptail --clear --title "$TITLE" --menu "\nSelect Timezone:" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)
        # Timezone country
        items=$(ls "/usr/share/zoneinfo/${timezone}/")
        options=() && for item in ${items}; do options+=("${item}" ""); done
        timezone_country=$(whiptail --clear --title "$TITLE" --menu "\nSelect Timezone:" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)
        # Set timezone
        user_input="${timezone}/${timezone_country}"
    fi

    # Check timezone finally
    if [ ! -f "/usr/share/zoneinfo/${user_input}" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Timezone '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    else
        ARCH_OS_TIMEZONE="$user_input"
    fi

    # Set locale
    local user_input="$ARCH_OS_LOCALE_LANG"
    [ -z "$user_input" ] && user_input='?'
    local desc='Enter "?" to select from menu\n\nExample: "en_US" or "de_DE"'
    user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nSet locale\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

    # If locale is null
    if [ -z "$user_input" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Locale is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_LOCALE_LANG=""
        ARCH_OS_LOCALE_GEN_LIST=""
        create_config
        return 1
    fi

    # Check if user want select locale from menu
    if [ "$user_input" = "?" ]; then
        clear && echo "Loading..."
        items=$(/usr/bin/ls /usr/share/i18n/locales | grep -v "@")
        options=()
        for item in ${items}; do
            # Add only available locales (intense command)
            # shellcheck disable=SC2001
            if grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<<"$item") " /etc/locale.gen; then
                options+=("${item}" "")
            fi
        done
        clear && locales=$(whiptail --clear --title "$TITLE" --menu "\nSelect Locale (type char to search):" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)
        # Set locale
        user_input="$locales"
    fi

    # Check locale finally
    # shellcheck disable=SC2001
    if ! grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<<"$user_input") " /etc/locale.gen; then
        whiptail --clear --title "$TITLE" --msgbox "Locale '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
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
    create_config
    return 0
}

tui_set_keyboard() {

    # Input console keyboard keymap
    local user_input="$ARCH_OS_VCONSOLE_KEYMAP"
    [ -z "$user_input" ] && user_input='?'
    local desc='Enter "?" to select from menu\n\nExample: "de-latin1-nodeadkeys" or "us"'
    user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nSet console keyboard keymap\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

    # If keymap null
    if [ -z "$user_input" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Console Keymap is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_VCONSOLE_KEYMAP=""
        create_config
        return 1
    fi

    # Check if user want select keymap from menu
    if [ "$user_input" = "?" ]; then
        clear && echo "Loading..."
        items=$(find /usr/share/kbd/keymaps/ -type f -printf "%f\n" | sort -V | grep -v "README")
        options=()
        for item in ${items}; do
            # Add only available keymap (intense command)
            if localectl list-keymaps | grep -Fxq "${item%%.*}"; then
                options+=("${item%%.*}" "")
            fi
        done
        clear && keymap=$(whiptail --clear --title "$TITLE" --menu "\nSelect Keymap (type char to search):" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)
        # Set keymap
        user_input="$keymap"
    fi

    # Finally check & set console keymap
    if ! localectl list-keymaps | grep -Fxq "$user_input"; then
        whiptail --clear --title "$TITLE" --msgbox "Error: Keyboard layout '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 1
    else
        ARCH_OS_VCONSOLE_KEYMAP="$user_input"
    fi

    # Success
    create_config
    return 0
}

tui_set_user() {
    ARCH_OS_USERNAME=$(whiptail --clear --title "$TITLE" --inputbox "\nEnter Arch OS Username" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_OS_USERNAME" 3>&1 1>&2 2>&3)
    if [ -z "$ARCH_OS_USERNAME" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Arch OS Username is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        create_config # Remove username
        return 1
    fi
    # Success
    create_config
    return 0
}

tui_set_password() {
    local desc='Note: This password is also used for encryption (if enabled)'
    ARCH_OS_PASSWORD=$(whiptail --clear --title "$TITLE" --passwordbox "\nEnter Password\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
    if [ -z "$ARCH_OS_PASSWORD" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Password is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        create_config # Remove password
        return 1
    fi

    local password_check
    password_check=$(whiptail --clear --title "$TITLE" --passwordbox "\nEnter Password (again)" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
    if [ "$ARCH_OS_PASSWORD" != "$password_check" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Password not identical" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_PASSWORD=""
        create_config # Remove password
        return 1
    fi
    # Success
    create_config
    return 0
}

tui_set_disk() {
    # List available disks
    local disk_array=()
    while read -r disk_line; do
        disk_array+=("/dev/$disk_line")
        disk_array+=(" ($(lsblk -d -n -o SIZE /dev/"$disk_line"))")
    done < <(lsblk -I 8,259,254 -d -o KNAME -n)

    # If no disk found
    [ "${#disk_array[@]}" = "0" ] && whiptail --clear --title "$TITLE" --msgbox "No Disk found" "$TUI_HEIGHT" "$TUI_WIDTH" && return 1

    # Show TUI (select disk)
    ARCH_OS_DISK=$(whiptail --clear --title "$TITLE" --menu "\nChoose Installation Disk" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "${#disk_array[@]}" "${disk_array[@]}" 3>&1 1>&2 2>&3)

    # Handle result
    [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}p1" || ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}1"
    [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}p2" || ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}2"

    # Success
    create_config
    return 0
}

tui_set_encryption() {
    ARCH_OS_ENCRYPTION_ENABLED="false"
    if whiptail --clear --title "$TITLE" --yesno "Enable Disk Encryption?" --defaultno "$TUI_HEIGHT" "$TUI_WIDTH"; then
        ARCH_OS_ENCRYPTION_ENABLED="true"
    fi
    # Success
    create_config
    return 0
}

tui_set_bootsplash() {
    ARCH_OS_BOOTSPLASH_ENABLED="false"
    if whiptail --clear --title "$TITLE" --yesno "Install Bootsplash Animation (plymouth)?" --yes-button "Yes" --no-button "No" "$TUI_HEIGHT" "$TUI_WIDTH"; then
        ARCH_OS_BOOTSPLASH_ENABLED="true"
    fi
    # Success
    create_config
    return 0
}

tui_set_variant() {

    # Set driver
    local variant_array=()
    variant_array+=("desktop") && variant_array+=("Arch OS Desktop (Default)")
    variant_array+=("base") && variant_array+=("Arch OS Base (without Desktop)")
    variant_array+=("core") && variant_array+=("Arch OS Core (minimal Arch Linux)")
    ARCH_OS_VARIANT=$(whiptail --clear --title "$TITLE" --menu "\nChoose Arch OS Variant" --nocancel --notags --default-item "$ARCH_OS_VARIANT" "$TUI_HEIGHT" "$TUI_WIDTH" "${#variant_array[@]}" "${variant_array[@]}" 3>&1 1>&2 2>&3)
    if [ "$ARCH_OS_VARIANT" = "desktop" ]; then
        # Set driver
        local driver_array=()
        driver_array+=("mesa") && driver_array+=("Mesa Universal Graphics (Default)")
        driver_array+=("intel_i915") && driver_array+=("Intel HD Graphics (i915)")
        driver_array+=("nvidia") && driver_array+=("NVIDIA Graphics (nvidia-dkms)")
        driver_array+=("amd") && driver_array+=("AMD Graphics (xf86-video-amdgpu)")
        driver_array+=("ati") && driver_array+=("ATI Graphics (xf86-video-ati)")
        ARCH_OS_GRAPHICS_DRIVER=$(whiptail --clear --title "$TITLE" --menu "\nChoose Graphics Driver" --nocancel --notags --default-item "$ARCH_OS_GRAPHICS_DRIVER" "$TUI_HEIGHT" "$TUI_WIDTH" "${#driver_array[@]}" "${driver_array[@]}" 3>&1 1>&2 2>&3)

        # Set X11 keyboard layout
        local user_input="$ARCH_OS_X11_KEYBOARD_LAYOUT"
        [ -z "$user_input" ] && user_input='us'
        user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nEnter X11 (Xorg) keyboard layout\n\nExample: 'de' or 'us'" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)
        # If null
        if [ -z "$user_input" ]; then
            whiptail --clear --title "$TITLE" --msgbox "X11 keyboard layout is null" "$TUI_HEIGHT" "$TUI_WIDTH"
            ARCH_OS_X11_KEYBOARD_LAYOUT=""
            create_config
            return 1
        fi
        ARCH_OS_X11_KEYBOARD_LAYOUT="$user_input"

        # Set X11 keyboard variant
        local user_input="$ARCH_OS_X11_KEYBOARD_VARIANT"
        [ -z "$user_input" ] && user_input=''
        user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nEnter X11 (Xorg) keyboard variant\n\nExample: 'nodeadkeys' or leave empty for default" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)
        ARCH_OS_X11_KEYBOARD_VARIANT="$user_input"
    fi

    # Success
    create_config
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

wait && sleep 0.2

# ----------------------------------------------------------------------------------------------------
# WELCOME SCREEN
# ----------------------------------------------------------------------------------------------------

welcome_txt="
           █████  ██████   ██████ ██   ██      ██████  ███████ 
          ██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
          ███████ ██████  ██      ███████     ██    ██ ███████ 
          ██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
          ██   ██ ██   ██  ██████ ██   ██      ██████  ███████ 
                                 

                    Welcome to the Arch OS Installer!

    On the next screen you can select the properties of your Arch OS setup
      or your can edit the properties manually in 'installer.conf' file.
    "
whiptail --clear --title "$TITLE" --msgbox "$welcome_txt" "$TUI_HEIGHT" "$TUI_WIDTH"

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
    menu_entry_array+=("language") && menu_entry_array+=("$(print_menu_entry "Language" "${ARCH_OS_LOCALE_LANG}" "${ARCH_OS_TIMEZONE}")")
    menu_entry_array+=("keyboard") && menu_entry_array+=("$(print_menu_entry "Keyboard" "${ARCH_OS_VCONSOLE_KEYMAP}")")
    menu_entry_array+=("disk") && menu_entry_array+=("$(print_menu_entry "Disk" "${ARCH_OS_DISK}")")
    menu_entry_array+=("encrypt") && menu_entry_array+=("$(print_menu_entry "Encryption" "${ARCH_OS_ENCRYPTION_ENABLED}")")
    menu_entry_array+=("bootsplash") && menu_entry_array+=("$(print_menu_entry "Bootsplash" "${ARCH_OS_BOOTSPLASH_ENABLED}")")
    menu_variant="$ARCH_OS_VARIANT"
    [ "$menu_variant" = "desktop" ] && [ -z "${ARCH_OS_GRAPHICS_DRIVER}" ] && menu_variant=""
    [ "$menu_variant" = "desktop" ] && [ -z "${ARCH_OS_X11_KEYBOARD_LAYOUT}" ] && menu_variant=""
    menu_entry_array+=("variant") && menu_entry_array+=("$(print_menu_entry "Variant" "${menu_variant}")")
    menu_entry_array+=("") && menu_entry_array+=("") # Empty entry
    menu_entry_array+=("edit") && menu_entry_array+=("> Advanced Config")
    if [ "$TUI_POSITION" = "install" ]; then
        menu_entry_array+=("install") && menu_entry_array+=("> Continue Installation")
    else
        menu_entry_array+=("install") && menu_entry_array+=("x Continue Installation")
    fi

    # Open TUI menu
    menu_selection=$(whiptail --clear --title "$TITLE" --menu "\n" --ok-button "Ok" --cancel-button "Exit" --notags --default-item "$TUI_POSITION" "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#menu_entry_array[@]} / 2) + (${#menu_entry_array[@]} % 2)))" "${menu_entry_array[@]}" 3>&1 1>&2 2>&3) || exit

    # Handle result
    case "${menu_selection}" in

    "user")
        tui_set_user || continue
        ;;
    "password")
        tui_set_password || continue
        ;;
    "language")
        tui_set_language || continue
        ;;
    "keyboard")
        tui_set_keyboard || continue
        ;;
    "disk")
        tui_set_disk || continue
        ;;
    "encrypt")
        tui_set_encryption || continue
        ;;
    "bootsplash")
        tui_set_bootsplash || continue
        ;;
    "variant")
        tui_set_variant || continue
        ;;
    "edit")
        nano "$INSTALLER_CONFIG" </dev/tty || continue
        # Create config if something is missing after edit
        # shellcheck disable=SC1090
        source "$INSTALLER_CONFIG" && create_config
        ;;
    "install")
        check_config || continue
        # shellcheck disable=SC1090
        create_config && source "$INSTALLER_CONFIG"
        if whiptail --clear --title "$TITLE" --yesno "> Installation Properties\n\n$(head -100 "$INSTALLER_CONFIG" | tail +3)" --defaultno --yes-button "Edit" --no-button "Continue" --scrolltext "$TUI_HEIGHT" "$TUI_WIDTH"; then
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

if ! whiptail --clear --title "$TITLE" --yesno "Start Arch OS Linux Installation?\n\nAll data on ${ARCH_OS_DISK} will be DELETED!" --defaultno --yes-button "Start Installation" --no-button "Exit" "$TUI_HEIGHT" "$TUI_WIDTH"; then
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
        whiptail --clear --title "$TITLE" --msgbox "Arch OS Installation failed.\n\nDuration: ${duration_min} minutes and ${duration_sec} seconds\n\n$(echo -e "$logs" | tac)" --scrolltext 30 90

    else # Success = 0
        # Show TUI (duration time)
        whiptail --clear --title "$TITLE" --msgbox "Arch OS Installation successful.\n\nDuration: ${duration_min} minutes and ${duration_sec} seconds" "$TUI_HEIGHT" "$TUI_WIDTH"

        # Unmount
        wait # Wait for sub processes
        swapoff -a
        umount -A -R /mnt
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot

        if whiptail --clear --title "$TITLE" --yesno "Reboot now?" --defaultno --yes-button "Yes" --no-button "No" "$TUI_HEIGHT" "$TUI_WIDTH"; then
            wait && reboot
        fi
    fi

    # Exit
    clear && exit "$result_code"
}

# ----------------------------------------------------------------------------------------------------
# SET TRAP & TIME
# ----------------------------------------------------------------------------------------------------

# Set trap for logging on exit
trap 'trap_exit $?' EXIT

# Messure execution time
SECONDS=0

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////  ARCH OS INSTALLATION  //////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

(
    # Print nothing from stdin & stderr to console
    exec 3>&1 4>&2 # Saves file descriptors (new stdin: &3 new stderr: &4)

    # Log stdin & stderr to logfile
    exec &>"$LOG_FILE"
    #exec 1>/dev/null   # Log stdin to /dev/null
    #exec 2>"$LOG_FILE" # Log stderr to logfile

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
    [ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0

    # Update keyring
    pacman -Sy --noconfirm archlinux-keyring

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
    print_whiptail_info "Pacstrap System Packages (This takes about 10 minutes)"
    # ----------------------------------------------------------------------------------------------------

    # Core packages
    packages=()
    packages+=("base")
    packages+=("base-devel")
    packages+=("linux-firmware")
    packages+=("zram-generator")
    packages+=("networkmanager")
    packages+=("${ARCH_OS_KERNEL}")

    # Add microcode package
    [ -n "$ARCH_OS_MICROCODE" ] && packages+=("$ARCH_OS_MICROCODE")

    # Install core packages and initialize an empty pacman keyring in the target
    pacstrap -K /mnt "${packages[@]}"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Generate /etc/fstab"
    # ----------------------------------------------------------------------------------------------------

    genfstab -U /mnt >>/mnt/etc/fstab

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create Swap (zram)"
    # ----------------------------------------------------------------------------------------------------
    {
        # https://wiki.archlinux.org/title/Zram#Using_zram-generator
        echo '[zram0]'
        echo 'zram-size = ram / 2'
        echo 'compression-algorithm = zstd'
        echo 'swap-priority = 100'
        echo 'fs-type = swap'
    } >/mnt/etc/systemd/zram-generator.conf

    # Optimize swap on zram (https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram)
    {
        echo 'vm.swappiness = 180'
        echo 'vm.watermark_boost_factor = 0'
        echo 'vm.watermark_scale_factor = 125'
        echo 'vm.page-cluster = 0'
    } >/mnt/etc/sysctl.d/99-vm-zram-parameters.conf

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
    # Zswap should be disabled when using zram (https://github.com/archlinux/archinstall/issues/881)
    kernel_args_default="rw init=/usr/lib/systemd/systemd zswap.enabled=0 quiet splash vt.global_cursor_default=0"
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && kernel_args="rd.luks.name=$(blkid -s UUID -o value "${ARCH_OS_ROOT_PARTITION}")=cryptroot root=/dev/mapper/cryptroot ${kernel_args_default}"
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && kernel_args="root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_OS_ROOT_PARTITION}") ${kernel_args_default}"

    # Create Bootloader config
    {
        echo 'default arch.conf'
        echo 'console-mode auto'
        echo 'timeout 0'
        echo 'editor yes'
    } >/mnt/boot/loader/loader.conf

    # Create default boot entry
    {
        echo 'title   Arch OS'
        echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
        [ -n "$ARCH_OS_MICROCODE" ] && echo "initrd  /${ARCH_OS_MICROCODE}.img"
        echo "initrd  /initramfs-${ARCH_OS_KERNEL}.img"
        echo "options ${kernel_args}"
    } >/mnt/boot/loader/entries/arch.conf

    # Create fallback boot entry
    {
        echo 'title   Arch OS (Fallback)'
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

    arch-chroot /mnt systemctl enable NetworkManager                   # Network Manager
    arch-chroot /mnt systemctl enable fstrim.timer                     # SSD support
    arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service # Swap (zram-generator)
    arch-chroot /mnt systemctl enable systemd-oomd.service             # Out of memory killer (swap is required)
    arch-chroot /mnt systemctl enable systemd-boot-update.service      # Auto bootloader update
    arch-chroot /mnt systemctl enable systemd-timesyncd.service        # Sync time from internet after boot

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Bootsplash"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed plymouth git # git when core variant is used

        # Configure mkinitcpio
        sed -i "s/base systemd keyboard/base systemd plymouth keyboard/g" /mnt/etc/mkinitcpio.conf

        # Install Arch OS plymouth theme
        repo_url="https://aur.archlinux.org/plymouth-theme-arch-os.git"
        tmp_name=$(mktemp -u "/home/${ARCH_OS_USERNAME}/plymouth-theme-arch-os.XXXXXXXXXX")
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git clone "$repo_url" "$tmp_name"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "cd $tmp_name && makepkg -si --noconfirm"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- rm -rf "$tmp_name"

        # Set Theme & rebuild initram disk
        arch-chroot /mnt plymouth-set-default-theme -R arch-os
    else
        echo "> Skipped"
    fi

    # ////////////////////////////////////////////////////////////////////////////////////////////////////
    # //////////////////////////////////////////  ARCH OS BASE  //////////////////////////////////////////
    # ////////////////////////////////////////////////////////////////////////////////////////////////////

    if [ "$ARCH_OS_VARIANT" != "core" ]; then

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Install Arch OS Base Packages"
        # ----------------------------------------------------------------------------------------------------

        # Base packages
        packages=()
        packages+=("pacman-contrib")
        packages+=("reflector")
        packages+=("pkgfile")
        packages+=("git")
        packages+=("nano")

        # Install base packages
        arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}"

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Enable Arch OS Base Services"
        # ----------------------------------------------------------------------------------------------------

        # Base Services
        arch-chroot /mnt systemctl enable reflector.service    # Rank mirrors after boot (reflector)
        arch-chroot /mnt systemctl enable paccache.timer       # Discard cached/unused packages weekly (pacman-contrib)
        arch-chroot /mnt systemctl enable pkgfile-update.timer # Pkgfile update timer (pkgfile)

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Configure Pacman & Reflector"
        # ----------------------------------------------------------------------------------------------------

        # Configure parrallel downloads, colors & multilib
        sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
        sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf
        if [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ]; then
            sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
            arch-chroot /mnt pacman -Syy --noconfirm
        fi

        # Configure reflector service
        {
            echo "# Reflector config for the systemd service"
            echo "--save /etc/pacman.d/mirrorlist"
            [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && echo "--country ${ARCH_OS_REFLECTOR_COUNTRY}"
            echo "--completion-percent 95"
            echo "--protocol https"
            echo "--latest 5"
            echo "--sort rate"
        } >/mnt/etc/xdg/reflector/reflector.conf

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Configure System"
        # ----------------------------------------------------------------------------------------------------

        # Set nano environment
        {
            echo 'EDITOR=nano'
            echo 'VISUAL=nano'
        } >/mnt/etc/environment

        # Set Nano colors
        sed -i "s/^# set linenumbers/set linenumbers/" /mnt/etc/nanorc
        sed -i "s/^# set minibar/set minibar/" /mnt/etc/nanorc
        sed -i 's;^# include "/usr/share/nano/\*\.nanorc";include "/usr/share/nano/*.nanorc"\ninclude "/usr/share/nano/extra/*.nanorc";g' /mnt/etc/nanorc

        # Reduce shutdown timeout
        sed -i "s/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf

        # Set max VMAs (need for some apps/games)
        echo vm.max_map_count=1048576 >/mnt/etc/sysctl.d/vm.max_map_count.conf

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Install AUR Helper"
        # ----------------------------------------------------------------------------------------------------

        if [ "$ARCH_OS_AUR_HELPER" != "none" ] && [ -n "$ARCH_OS_AUR_HELPER" ]; then

            # Install AUR Helper as user
            repo_url="https://aur.archlinux.org/${ARCH_OS_AUR_HELPER}.git"
            tmp_name=$(mktemp -u "/home/${ARCH_OS_USERNAME}/${ARCH_OS_AUR_HELPER}.XXXXXXXXXX")
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git clone "$repo_url" "$tmp_name"
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "cd $tmp_name && makepkg -si --noconfirm"
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- rm -rf "$tmp_name"

            # Paru config
            if [ "$ARCH_OS_AUR_HELPER" = "paru" ] || [ "$ARCH_OS_AUR_HELPER" = "paru-bin" ] || [ "$ARCH_OS_AUR_HELPER" = "paru-git" ]; then
                sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf
                sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf
            fi
        else
            echo "> Skipped"
        fi

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Install Shell Enhancement"
        # ----------------------------------------------------------------------------------------------------

        if [ "$ARCH_OS_SHELL_ENHANCED_ENABLED" = "true" ]; then

            # Install packages
            arch-chroot /mnt pacman -S --noconfirm --needed fish starship eza bat neofetch mc btop man-db

            # Create config dirs for root & user
            mkdir -p "/mnt/root/.config/fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish"
            mkdir -p "/mnt/root/.config/neofetch" "/mnt/home/${ARCH_OS_USERNAME}/.config/neofetch"

            # shellcheck disable=SC2016
            { # Create fish config for root & user
                echo 'if status is-interactive'
                echo '    # Commands to run in interactive sessions can go here'
                echo 'end'
                echo ''
                echo '# https://wiki.archlinux.de/title/Fish#Troubleshooting'
                echo 'if status --is-login'
                echo '    set PATH $PATH /usr/bin /sbin'
                echo 'end'
                echo ''
                echo '# Disable welcome message'
                echo 'set fish_greeting'
                echo ''
                echo '# Colorize man pages (bat)'
                echo -n 'export MANPAGER="sh -c ' && echo -n "'col -bx | bat -l man -p'" && echo '"'
                echo 'export MANROFFOPT="-c"'
                echo ''
                echo '# Source user aliases'
                echo 'source "$HOME/.config/fish/aliases.fish"'
                echo ''
                echo '# Source starship promt'
                echo 'starship init fish | source'
            } | tee "/mnt/root/.config/fish/config.fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish/config.fish" >/dev/null

            { # Create fish aliases for root & user
                echo 'alias ls="eza --color=always --group-directories-first"'
                echo 'alias diff="diff --color=auto"'
                echo 'alias grep="grep --color=auto"'
                echo 'alias ip="ip -color=auto"'
                echo 'alias lt="ls -Tal"'
                echo 'alias open="xdg-open"'
                echo 'alias fetch="neofetch"'
                echo 'alias logs="systemctl --failed; echo; journalctl -p 3 -b"'
                echo 'alias q="exit"'
            } | tee "/mnt/root/.config/fish/aliases.fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish/aliases.fish" >/dev/null

            { # Create starship config for root & user
                echo "# Get editor completions based on the config schema"
                echo "\"\$schema\" = 'https://starship.rs/config-schema.json'"
                echo ""
                echo "# Wait 10 milliseconds for starship to check files under the current directory"
                echo "scan_timeout = 10"
                echo ""
                echo "# Set command timeout"
                echo "command_timeout = 10000"
                echo ""
                echo "# Inserts a blank line between shell prompts"
                echo "add_newline = true"
                echo ""
                echo "# Replace the promt symbol"
                echo "[character]"
                echo "success_symbol = '[>](bold purple)'"
                echo ""
                echo "# Disable the package module, hiding it from the prompt completely"
                echo "[package]"
                echo "disabled = true"
            } | tee "/mnt/root/.config/starship.toml" "/mnt/home/${ARCH_OS_USERNAME}/.config/starship.toml" >/dev/null

            # shellcheck disable=SC2028,SC2016
            { # Create neofetch config for root & user
                echo '# https://github.com/dylanaraps/neofetch/wiki/Customizing-Info'
                echo ''
                echo 'print_info() {'
                echo '    prin'
                echo '    prin "Distro\t" "Arch OS"'
                echo '    info "Kernel\t" kernel'
                #echo '    info "Host\t" model'
                echo '    info "CPU\t" cpu'
                echo '    info "GPU\t" gpu'
                echo '    prin'
                echo '    info "Desktop\t" de'
                echo '    prin "Window\t" "$([ $XDG_SESSION_TYPE = "x11" ] && echo X11 || echo Wayland)"'
                echo '    info "Manager\t" wm'
                echo '    info "Shell\t" shell'
                echo '    info "Terminal\t" term'
                echo '    prin'
                echo '    info "Disk\t" disk'
                echo '    info "Memory\t" memory'
                echo '    info "IP\t" local_ip'
                echo '    info "Uptime\t" uptime'
                echo '    info "Packages\t" packages'
                echo '    prin'
                echo '    prin "$(color 1) ● \n $(color 2) ● \n $(color 3) ● \n $(color 4) ● \n $(color 5) ● \n $(color 6) ● \n $(color 7) ● \n $(color 8) ●"'
                echo '}'
                echo ''
                echo '# Config'
                echo 'separator=" → "'
                echo 'ascii_distro="auto"'
                echo 'ascii_bold="on"'
                echo 'ascii_colors=(5 5 5 5 5 5)'
                echo 'bold="on"'
                echo 'colors=(7 7 7 7 7 7)'
                echo 'gap=8'
                echo 'os_arch="off"'
                echo 'shell_version="off"'
                echo 'cpu_speed="off"'
                echo 'cpu_brand="on"'
                echo 'cpu_cores="off"'
                echo 'cpu_temp="off"'
                echo 'memory_display="info"'
                echo 'memory_percent="on"'
                echo 'memory_unit="gib"'
                echo 'disk_display="info"'
                echo 'disk_subtitle="none"'
            } | tee "/mnt/root/.config/neofetch/config.conf" "/mnt/home/${ARCH_OS_USERNAME}/.config/neofetch/config.conf" >/dev/null

            # Set correct user permissions
            arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}/"

            # Set Shell for root & user
            arch-chroot /mnt chsh -s /usr/bin/fish
            arch-chroot /mnt chsh -s /usr/bin/fish "$ARCH_OS_USERNAME"
        else
            # Install bash-completion
            arch-chroot /mnt pacman -S --noconfirm --needed bash-completion
        fi

        # ----------------------------------------------------------------------------------------------------
        # END ARCH OS BASE
        # ----------------------------------------------------------------------------------------------------

    else
        PROGRESS_COUNT=27 # Skip progress
    fi

    # ////////////////////////////////////////////////////////////////////////////////////////////////////
    # /////////////////////////////////////////  ARCH OS DESKTOP  ////////////////////////////////////////
    # ////////////////////////////////////////////////////////////////////////////////////////////////////

    if [ "$ARCH_OS_VARIANT" = "desktop" ]; then

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Install GNOME Packages (This takes about 15 minutes)"
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

        # GNOME legacy Indicator support (need for systray) (51 packages)
        packages+=("libappindicator-gtk2")
        packages+=("libappindicator-gtk3")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libappindicator-gtk2")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libappindicator-gtk3")

        # Audio
        packages+=("pipewire")                                                        # Pipewire
        packages+=("pipewire-alsa")                                                   # Replacement for alsa
        packages+=("pipewire-pulse")                                                  # Replacement for pulse
        packages+=("pipewire-jack")                                                   # Replacement for jack
        packages+=("wireplumber")                                                     # Pipewire session manager
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-pipewire")      # Pipewire 32 bit
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-pipewire-jack") # Replacement for jack 32 bit

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
        packages+=("unzip")
        packages+=("unrar")
        packages+=("tar")

        # Codecs
        packages+=("gst-libav")
        packages+=("gst-plugin-pipewire")
        packages+=("gst-plugins-ugly")
        packages+=("libdvdcss")
        packages+=("libheif")

        # Optimization
        packages+=("gamemode")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-gamemode")

        # Fonts
        packages+=("noto-fonts")
        packages+=("noto-fonts-emoji")
        packages+=("ttf-firacode-nerd")
        packages+=("ttf-liberation")
        packages+=("ttf-dejavu")

        # Driver
        #packages+=("xf86-input-synaptics") # For some legacy touchpads

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}"

        # Add user to gamemode group
        arch-chroot /mnt gpasswd -a "$ARCH_OS_USERNAME" gamemode

        # ----------------------------------------------------------------------------------------------------

        # VM Guest support (if VM detected)
        if [ "$ARCH_OS_VM_SUPPORT_ENABLED" = "true" ]; then
            hypervisor=$(systemd-detect-virt)
            case $hypervisor in
            kvm)
                print_whiptail_info "KVM has been detected, setting up guest tools."
                arch-chroot /mnt pacman -S --noconfirm --needed spice spice-vdagent spice-protocol spice-gtk qemu-guest-agent
                arch-chroot /mnt systemctl enable qemu-guest-agent
                ;;
            vmware)
                print_whiptail_info "VMWare Workstation/ESXi has been detected, setting up guest tools."
                arch-chroot /mnt pacman -S --noconfirm --needed open-vm-tools
                arch-chroot /mnt systemctl enable vmtoolsd
                arch-chroot /mnt systemctl enable vmware-vmblock-fuse
                ;;
            oracle)
                print_whiptail_info "VirtualBox has been detected, setting up guest tools."
                arch-chroot /mnt pacman -S --noconfirm --needed virtualbox-guest-utils
                arch-chroot /mnt systemctl enable vboxservice
                ;;
            microsoft)
                print_whiptail_info "Hyper-V has been detected, setting up guest tools."
                arch-chroot /mnt pacman -S --noconfirm --needed hyperv
                arch-chroot /mnt systemctl enable hv_fcopy_daemon
                arch-chroot /mnt systemctl enable hv_kvp_daemon
                arch-chroot /mnt systemctl enable hv_vss_daemon
                ;;
            none)
                print_whiptail_info "No VM detected"
                # Do nothing
                ;;
            esac
        fi

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
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/cups.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/fish.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/btop.desktop"

        # ----------------------------------------------------------------------------------------------------
        print_whiptail_info "Install Graphics Driver"
        # ----------------------------------------------------------------------------------------------------

        case "${ARCH_OS_GRAPHICS_DRIVER}" in

        "mesa") # https://wiki.archlinux.org/title/OpenGL#Installation
            packages=()
            packages+=("mesa")
            packages+=("mesa-utils")
            packages+=("vkd3d")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa-utils")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
            arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}"
            ;;

        "intel_i915") # https://wiki.archlinux.org/title/Intel_graphics#Installation
            packages=()
            packages+=("vulkan-intel")
            packages+=("vkd3d")
            packages+=("libva-intel-driver")
            packages+=("intel-media-driver") # do we need this?
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vulkan-intel")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libva-intel-driver")
            arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}"
            sed -i "s/^MODULES=(.*)/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf
            arch-chroot /mnt mkinitcpio -P
            ;;

        "nvidia") # https://wiki.archlinux.org/title/NVIDIA#Installation
            packages=()
            packages+=("${ARCH_OS_KERNEL}-headers")
            packages+=("nvidia-dkms")
            packages+=("nvidia-settings")
            packages+=("nvidia-utils")
            packages+=("opencl-nvidia")
            packages+=("vkd3d")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-nvidia-utils")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-opencl-nvidia")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
            arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}"
            # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
            # Alternative (slow boot, bios logo twice, but correct plymouth resolution):
            #sed -i "s/zswap.enabled=0 quiet/zswap.enabled=0 nvidia_drm.modeset=1 nvidia_drm.fbdev=1 quiet/g" /mnt/boot/loader/entries/arch.conf
            mkdir -p /mnt/etc/modprobe.d/ && echo -e 'options nvidia_drm modeset=1 fbdev=1' >/mnt/etc/modprobe.d/nvidia.conf
            sed -i "s/^MODULES=(.*)/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /mnt/etc/mkinitcpio.conf
            # https://wiki.archlinux.org/title/NVIDIA#pacman_hook
            mkdir -p /mnt/etc/pacman.d/hooks/
            {
                echo "[Trigger]"
                echo "Operation=Install"
                echo "Operation=Upgrade"
                echo "Operation=Remove"
                echo "Type=Package"
                echo "Target=nvidia"
                echo "Target=${ARCH_OS_KERNEL}"
                echo "# Change the linux part above if a different kernel is used"
                echo ""
                echo "[Action]"
                echo "Description=Update NVIDIA module in initcpio"
                echo "Depends=mkinitcpio"
                echo "When=PostTransaction"
                echo "NeedsTargets"
                echo "Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'"
            } >/mnt/etc/pacman.d/hooks/nvidia.hook
            # Enable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
            [ ! -f /mnt/etc/udev/rules.d/61-gdm.rules ] && mkdir -p /mnt/etc/udev/rules.d/ && ln -s /dev/null /mnt/etc/udev/rules.d/61-gdm.rules
            # Rebuild initial ram disk
            arch-chroot /mnt mkinitcpio -P
            ;;

        "amd") # https://wiki.archlinux.org/title/AMDGPU#Installation
            packages=()
            packages+=("xf86-video-amdgpu")
            packages+=("libva-mesa-driver")
            packages+=("vulkan-radeon")
            packages+=("mesa-vdpau")
            packages+=("vkd3d")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libva-mesa-driver")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vulkan-radeon")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa-vdpau")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
            arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}"
            sed -i "s/^MODULES=(.*)/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf
            arch-chroot /mnt mkinitcpio -P
            ;;

        "ati") # https://wiki.archlinux.org/title/ATI#Installation
            packages=()
            packages+=("xf86-video-ati")
            packages+=("libva-mesa-driver")
            packages+=("mesa-vdpau")
            packages+=("vkd3d")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libva-mesa-driver")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa-vdpau")
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
            arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}"
            sed -i "s/^MODULES=(.*)/MODULES=(amdgpu radeon)/g" /mnt/etc/mkinitcpio.conf
            arch-chroot /mnt mkinitcpio -P
            ;;

        esac

    # ----------------------------------------------------------------------------------------------------
    # END ARCH OS DESKTOP
    # ----------------------------------------------------------------------------------------------------

    else
        # Skip desktop progresses
        PROGRESS_COUNT=39
    fi

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

) | whiptail --clear --title "$TITLE" --gauge "Start Arch Installation..." 7 "$TUI_WIDTH" 0

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////// INSTALLATION FINISHED ///////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Goto exit trap (see above)
exit 0
