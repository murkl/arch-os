#!/usr/bin/env bash
clear

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////////// ARCH OS SETUP ///////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

VERSION='1.2.7'

# ----------------------------------------------------------------------------------------------------
# SOURCE:   https://github.com/murkl/arch-os
# AUTOR:    murkl
# ORIGIN:   Germany
# LICENCE:  GPL-V2
#
# CONFIGURATION
# ----------------------------------------------------------------------------------------------------

set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -u          # Uninitialized variables trigger errors
#set -e          # Terminate if any command exits with a non-zero
#set -E          # ERR trap inherited by shell functions (errtrace)

# ----------------------------------------------------------------------------------------------------
# SCRIPT VARIABLES
# ----------------------------------------------------------------------------------------------------

TITLE="Arch OS Setup ${VERSION}"
CONFIG_FILE="./installer.conf"
TUI_WIDTH="80"
TUI_HEIGHT="20"
TUI_POSITION=""
PROGRESS_TITLE=""
PROGRESS_COUNT=0
PROGRESS_TOTAL=45

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
ARCH_OS_X11_KEYBOARD_MODEL=""
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
# TRAP FUNCTIONS
# ----------------------------------------------------------------------------------------------------

# This trap is called on error in setup menu: ERR
# shellcheck disable=SC2317
trap_error_setup() {

    local result_code="$?"
    local line_no="$1"
    local func_name="$2"

    # Print
    echo "ERROR: Command '${BASH_COMMAND}' failed with exit code ${result_code} in function '${func_name}' (line ${line_no})" >&2
}

# ----------------------------------------------------------------------------------------------------

# This trap is called on error in installation: ERR
# shellcheck disable=SC2317
trap_error_install() {

    local result_code="$?"
    local line_no="$1"
    local func_name="$2"

    # Print to stderr (will be logged in installer.log)
    echo "###ERR" >&2 # Print marker for exit logging trap
    echo "Progress:  '${PROGRESS_TITLE}' failed with exit code ${result_code}" >&2
    echo "Command:   '${BASH_COMMAND}' in function '${func_name}' (line ${line_no})" >&2
}

# ----------------------------------------------------------------------------------------------------

# This trap is called after installation: EXIT (sucess & failed)
# shellcheck disable=SC2317
trap_exit_install() {

    # Result code
    local result_code="$?"

    # Calc duration
    local duration=$SECONDS # This is set before install starts
    local duration_min="$((duration / 60))"
    local duration_sec="$((duration % 60))"

    # Check exit return code
    if [ "$result_code" -gt 0 ]; then # Error >= 1

        # Read in installer.log (inverted)
        local log_whiptail=""
        local line=""
        while read -r line; do
            [ "$line" = "###!ERR" ] && break        # If first marker (from bottom) found, break loop
            [ -z "$line" ] && continue              # Skip newline
            log_whiptail="${log_whiptail}\n${line}" # Append log
        done <<<"$(tac "$LOG_FILE")"                # Read logfile inverted (from bottom)

        # Invert whiptail log
        log_whiptail="$(echo -e "$log_whiptail" | tac)"

        # Show TUI Failed (duration & log)
        local tui_txt="Arch OS Installation failed after ${duration_min} minutes and ${duration_sec} seconds.\n\n${log_whiptail}"
        whiptail --clear --title "$TITLE" --msgbox "$tui_txt" --scrolltext "$TUI_HEIGHT" "$TUI_WIDTH"

    else # Success = 0

        # Unmount
        wait # Wait for sub processes
        swapoff -a
        umount -A -R /mnt
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot

        # Show TUI Sucess
        local tui_txt="Arch OS successfully installed after ${duration_min} minutes and ${duration_sec} seconds.\n\nReboot now?"
        if whiptail --clear --title "$TITLE" --yesno "$tui_txt" --defaultno --yes-button "Yes" --no-button "No" "$TUI_HEIGHT" "$TUI_WIDTH"; then
            wait && reboot
        fi
    fi

    # Exit
    clear && exit "$result_code"
}

# ----------------------------------------------------------------------------------------------------
# HELPER FUNCTIONS
# ----------------------------------------------------------------------------------------------------

print_menu_entry() {

    local key="$1" && shift
    local val="$1" && shift

    # Trim spaces
    val=$(echo "$val" | xargs)

    # If another arg is null, set val=null
    for arg in "${@}"; do [ -z "$arg" ] && val=""; done

    # Locate spaces
    local spaces=""
    for ((i = ${#key}; i < 12; i++)); do spaces="${spaces} "; done

    # Set default value
    [ -z "$val" ] && val='?'

    # Print menu entry text
    echo "${key} ${spaces} ->  $val"
}

# ----------------------------------------------------------------------------------------------------

print_whiptail_info() {

    # Set current progress title
    PROGRESS_TITLE="$1"

    # Print title for logging
    echo ">>> ${PROGRESS_TITLE}" >&1

    # Increment progress counter
    ((PROGRESS_COUNT += 1))

    # Check if max and increase
    if [ "$PROGRESS_COUNT" -ge "$PROGRESS_TOTAL" ]; then
        PROGRESS_TOTAL=$((PROGRESS_COUNT + 1))
    fi

    # Print percent & title for whiptail (uses descriptor 3 as stdin)
    echo -e "XXX\n$((PROGRESS_COUNT * 100 / PROGRESS_TOTAL))\n${PROGRESS_TITLE}...\nXXX" >&3
}

# ----------------------------------------------------------------------------------------------------
# CONFIG FUNCTIONS
# ----------------------------------------------------------------------------------------------------

set_default_properties() {

    # Set default values (if not already set)
    [ -z "$ARCH_OS_HOSTNAME" ] && ARCH_OS_HOSTNAME="arch-os"
    [ -z "$ARCH_OS_KERNEL" ] && ARCH_OS_KERNEL="linux-zen"
    [ -z "$ARCH_OS_VM_SUPPORT_ENABLED" ] && ARCH_OS_VM_SUPPORT_ENABLED="true"
    [ -z "$ARCH_OS_SHELL_ENHANCED_ENABLED" ] && ARCH_OS_SHELL_ENHANCED_ENABLED="true"
    [ -z "$ARCH_OS_AUR_HELPER" ] && ARCH_OS_AUR_HELPER="paru"
    [ -z "$ARCH_OS_MULTILIB_ENABLED" ] && ARCH_OS_MULTILIB_ENABLED="true"
    [ -z "$ARCH_OS_ECN_ENABLED" ] && ARCH_OS_ECN_ENABLED="true"
    [ -z "$ARCH_OS_X11_KEYBOARD_MODEL" ] && ARCH_OS_X11_KEYBOARD_MODEL="pc105"
    #[ -z "$ARCH_OS_VCONSOLE_FONT" ] && ARCH_OS_VCONSOLE_FONT="eurlatgr"
    #[ -z "$ARCH_OS_REFLECTOR_COUNTRY" ] && ARCH_OS_REFLECTOR_COUNTRY="Germany,France"

    # Detect microcode if empty
    [ -z "$ARCH_OS_MICROCODE" ] && grep -E "GenuineIntel" <<<"$(lscpu)" && ARCH_OS_MICROCODE="intel-ucode"
    [ -z "$ARCH_OS_MICROCODE" ] && grep -E "AuthenticAMD" <<<"$(lscpu)" && ARCH_OS_MICROCODE="amd-ucode"

    return 0
}

# ----------------------------------------------------------------------------------------------------

check_properties() {

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

# ----------------------------------------------------------------------------------------------------

generate_properties_file() {
    {
        echo "# ${TITLE} (generated: $(date --utc '+%Y-%m-%d %H:%M') UTC)"
        echo "ARCH_OS_HOSTNAME='${ARCH_OS_HOSTNAME}'"
        echo "ARCH_OS_USERNAME='${ARCH_OS_USERNAME}'"
        echo "ARCH_OS_DISK='${ARCH_OS_DISK}'"
        echo "ARCH_OS_BOOT_PARTITION='${ARCH_OS_BOOT_PARTITION}'"
        echo "ARCH_OS_ROOT_PARTITION='${ARCH_OS_ROOT_PARTITION}'"
        echo "ARCH_OS_ENCRYPTION_ENABLED='${ARCH_OS_ENCRYPTION_ENABLED}'"
        echo "ARCH_OS_TIMEZONE='${ARCH_OS_TIMEZONE}'"
        echo "ARCH_OS_LOCALE_LANG='${ARCH_OS_LOCALE_LANG}'"
        echo "ARCH_OS_LOCALE_GEN_LIST=(${ARCH_OS_LOCALE_GEN_LIST[*]@Q})"
        echo "ARCH_OS_VCONSOLE_KEYMAP='${ARCH_OS_VCONSOLE_KEYMAP}'"
        echo "ARCH_OS_VCONSOLE_FONT='${ARCH_OS_VCONSOLE_FONT}'"
        echo "ARCH_OS_KERNEL='${ARCH_OS_KERNEL}'"
        echo "ARCH_OS_MICROCODE='${ARCH_OS_MICROCODE}'"
        echo "ARCH_OS_ECN_ENABLED='${ARCH_OS_ECN_ENABLED}'"
        echo "ARCH_OS_BOOTSPLASH_ENABLED='${ARCH_OS_BOOTSPLASH_ENABLED}'"
        echo "ARCH_OS_VARIANT='${ARCH_OS_VARIANT}'"
        echo "ARCH_OS_SHELL_ENHANCED_ENABLED='${ARCH_OS_SHELL_ENHANCED_ENABLED}'"
        echo "ARCH_OS_AUR_HELPER='${ARCH_OS_AUR_HELPER}'"
        echo "ARCH_OS_MULTILIB_ENABLED='${ARCH_OS_MULTILIB_ENABLED}'"
        echo "ARCH_OS_REFLECTOR_COUNTRY='${ARCH_OS_REFLECTOR_COUNTRY}'"
        echo "ARCH_OS_GRAPHICS_DRIVER='${ARCH_OS_GRAPHICS_DRIVER}'"
        echo "ARCH_OS_X11_KEYBOARD_LAYOUT='${ARCH_OS_X11_KEYBOARD_LAYOUT}'"
        echo "ARCH_OS_X11_KEYBOARD_MODEL='${ARCH_OS_X11_KEYBOARD_MODEL}'"
        echo "ARCH_OS_X11_KEYBOARD_VARIANT='${ARCH_OS_X11_KEYBOARD_VARIANT}'"
        echo "ARCH_OS_VM_SUPPORT_ENABLED='${ARCH_OS_VM_SUPPORT_ENABLED}'"
    } >"$CONFIG_FILE"
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

    # Whiptail
    clear && user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nSet Timezone (auto detected)\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

    # If user timezone input is null
    if [ -z "$user_input" ]; then

        # Whiptail
        whiptail --clear --title "$TITLE" --msgbox "Timezone is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_TIMEZONE=""
        return 0
    fi

    # Check if user want select timezone from menu
    if [ "$user_input" = "?" ]; then
        local user_input items options timezone timezone_country
        items=$(/usr/bin/ls -l /usr/share/zoneinfo/ | grep '^d' | grep -v "right" | grep -v "posix" | gawk -F':[0-9]* ' '/:/{print $2}')
        options=() && for item in ${items}; do options+=("${item}" ""); done

        # Whiptail
        timezone=$(whiptail --clear --title "$TITLE" --menu "\nSelect Timezone:" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)

        # Timezone country
        items=$(/usr/bin/ls "/usr/share/zoneinfo/${timezone}/")
        options=() && for item in ${items}; do options+=("${item}" ""); done
        timezone_country=$(whiptail --clear --title "$TITLE" --menu "\nSelect Timezone:" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)

        # Set timezone
        user_input="${timezone}/${timezone_country}"
    fi

    # Check timezone finally
    if [ ! -f "/usr/share/zoneinfo/${user_input}" ]; then

        # Whiptail
        whiptail --clear --title "$TITLE" --msgbox "Timezone '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 0
    else
        ARCH_OS_TIMEZONE="$user_input"
    fi

    # Set locale
    local user_input="$ARCH_OS_LOCALE_LANG"
    [ -z "$user_input" ] && user_input='?'
    local desc='Enter "?" to select from menu\n\nExample: "en_US" or "de_DE"'

    # Whiptail
    user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nSet locale\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

    # If locale is null
    if [ -z "$user_input" ]; then

        # Whiptail
        whiptail --clear --title "$TITLE" --msgbox "Locale is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_LOCALE_LANG=""
        ARCH_OS_LOCALE_GEN_LIST=""
        return 0
    fi

    # Check if user want select locale from menu
    if [ "$user_input" = "?" ]; then
        clear && echo "Loading..."
        local user_input items options locales
        items=$(/usr/bin/ls /usr/share/i18n/locales | grep -v "@")
        options=()
        for item in ${items}; do
            # Add only available locales (intense command)
            # shellcheck disable=SC2001
            if grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<<"$item") " /etc/locale.gen; then
                options+=("${item}" "")
            fi
        done

        # Whiptail
        clear && locales=$(whiptail --clear --title "$TITLE" --menu "\nSelect Locale (type char to search):" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)

        # Set locale
        user_input="$locales"
    fi

    # Check locale finally
    # shellcheck disable=SC2001
    if ! grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<<"$user_input") " /etc/locale.gen; then

        # Whiptail
        whiptail --clear --title "$TITLE" --msgbox "Locale '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 0
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

# ----------------------------------------------------------------------------------------------------

tui_set_keyboard() {

    # Input console keyboard keymap
    local user_input="$ARCH_OS_VCONSOLE_KEYMAP"
    [ -z "$user_input" ] && user_input='?'
    local desc='Enter "?" to select from menu\n\nExample: "de-latin1-nodeadkeys" or "us"'

    # Whiptail
    user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nSet console keyboard keymap\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

    # If keymap null
    if [ -z "$user_input" ]; then

        # Whiptail
        whiptail --clear --title "$TITLE" --msgbox "Console Keymap is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_VCONSOLE_KEYMAP=""
        return 0
    fi

    # Check if user want select keymap from menu
    if [ "$user_input" = "?" ]; then
        clear && echo "Loading..."
        local user_input items options keymap
        items=$(find /usr/share/kbd/keymaps/ -type f -printf "%f\n" | sort -V | grep -v "README")
        options=()
        for item in ${items}; do

            # Add only available keymap (intense command)
            if localectl list-keymaps | grep -Fxq "${item%%.*}"; then
                options+=("${item%%.*}" "")
            fi
        done

        # Whiptail
        clear && keymap=$(whiptail --clear --title "$TITLE" --menu "\nSelect Keymap (type char to search):" $TUI_HEIGHT $TUI_WIDTH 10 "${options[@]}" 3>&1 1>&2 2>&3)

        # Set keymap
        user_input="$keymap"
    fi

    # Finally check & set console keymap
    if ! localectl list-keymaps | grep -Fxq "$user_input"; then
        whiptail --clear --title "$TITLE" --msgbox "Error: Keyboard layout '${user_input}' is not supported." "$TUI_HEIGHT" "$TUI_WIDTH"
        return 0
    else
        ARCH_OS_VCONSOLE_KEYMAP="$user_input"
    fi

    # Success
    return 0
}

# ----------------------------------------------------------------------------------------------------

tui_set_user() {

    ARCH_OS_USERNAME=$(whiptail --clear --title "$TITLE" --inputbox "\nEnter Arch OS Username" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_OS_USERNAME" 3>&1 1>&2 2>&3)
    if [ -z "$ARCH_OS_USERNAME" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Arch OS Username is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        return 0
    fi

    # Success
    return 0
}

# ----------------------------------------------------------------------------------------------------

tui_set_password() {

    local desc='Note: This password is also used for encryption (if enabled)'
    ARCH_OS_PASSWORD=$(whiptail --clear --title "$TITLE" --passwordbox "\nEnter Password\n\n${desc}" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
    if [ -z "$ARCH_OS_PASSWORD" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Password is null" "$TUI_HEIGHT" "$TUI_WIDTH"
        return 0
    fi

    local password_check
    password_check=$(whiptail --clear --title "$TITLE" --passwordbox "\nEnter Password (again)" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
    if [ "$ARCH_OS_PASSWORD" != "$password_check" ]; then
        whiptail --clear --title "$TITLE" --msgbox "Password not identical" "$TUI_HEIGHT" "$TUI_WIDTH"
        ARCH_OS_PASSWORD=""
        return 0
    fi

    # Success
    return 0
}

# ----------------------------------------------------------------------------------------------------

tui_set_disk() {

    # List available disks
    local disk_array=()
    while read -r disk_line; do
        disk_array+=("/dev/$disk_line")
        disk_array+=(" ($(lsblk -d -n -o SIZE /dev/"$disk_line"))")
    done < <(lsblk -I 8,259,254 -d -o KNAME -n)

    # If no disk found
    [ "${#disk_array[@]}" = "0" ] && whiptail --clear --title "$TITLE" --msgbox "No Disk found" "$TUI_HEIGHT" "$TUI_WIDTH" && return 0

    # Show TUI (select disk)
    ARCH_OS_DISK=$(whiptail --clear --title "$TITLE" --menu "\nChoose Installation Disk" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "${#disk_array[@]}" "${disk_array[@]}" 3>&1 1>&2 2>&3)

    # Handle result
    [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}p1" || ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}1"
    [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}p2" || ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}2"

    # Success
    return 0
}

# ----------------------------------------------------------------------------------------------------

tui_set_encryption() {

    ARCH_OS_ENCRYPTION_ENABLED="false"
    if whiptail --clear --title "$TITLE" --yesno "Enable Disk Encryption?" --defaultno "$TUI_HEIGHT" "$TUI_WIDTH"; then
        ARCH_OS_ENCRYPTION_ENABLED="true"
    fi

    # Success
    return 0
}

# ----------------------------------------------------------------------------------------------------

tui_set_bootsplash() {

    ARCH_OS_BOOTSPLASH_ENABLED="false"
    if whiptail --clear --title "$TITLE" --yesno "Install Bootsplash Animation (plymouth)?" --yes-button "Yes" --no-button "No" "$TUI_HEIGHT" "$TUI_WIDTH"; then
        ARCH_OS_BOOTSPLASH_ENABLED="true"
    fi

    # Success
    return 0
}

# ----------------------------------------------------------------------------------------------------

tui_set_variant() {

    # Create variant array
    local variant_array=()
    variant_array+=("desktop") && variant_array+=("Arch OS Desktop (Default)")
    variant_array+=("base") && variant_array+=("Arch OS Base (without Desktop)")
    variant_array+=("core") && variant_array+=("Arch OS Core (minimal Arch Linux)")

    # Whiptail
    ARCH_OS_VARIANT=$(whiptail --clear --title "$TITLE" --menu "\nChoose Arch OS Variant" --nocancel --notags --default-item "$ARCH_OS_VARIANT" "$TUI_HEIGHT" "$TUI_WIDTH" "${#variant_array[@]}" "${variant_array[@]}" 3>&1 1>&2 2>&3)
    if [ "$ARCH_OS_VARIANT" = "desktop" ]; then

        # Create driver array
        local driver_array=()
        driver_array+=("mesa") && driver_array+=("Mesa Universal Graphics (Default)")
        driver_array+=("intel_i915") && driver_array+=("Intel HD Graphics (i915)")
        driver_array+=("nvidia") && driver_array+=("NVIDIA Graphics (nvidia-dkms)")
        driver_array+=("amd") && driver_array+=("AMD Graphics (xf86-video-amdgpu)")
        driver_array+=("ati") && driver_array+=("ATI Graphics (xf86-video-ati)")

        # Whiptail
        ARCH_OS_GRAPHICS_DRIVER=$(whiptail --clear --title "$TITLE" --menu "\nChoose Graphics Driver" --nocancel --notags --default-item "$ARCH_OS_GRAPHICS_DRIVER" "$TUI_HEIGHT" "$TUI_WIDTH" "${#driver_array[@]}" "${driver_array[@]}" 3>&1 1>&2 2>&3)

        # Set X11 keyboard layout
        local user_input="$ARCH_OS_X11_KEYBOARD_LAYOUT"
        [ -z "$user_input" ] && user_input='us'

        # Whiptail
        user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nEnter X11 (Xorg) keyboard layout\n\nExample: 'de' or 'us'" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)

        # If keyboard layout is null
        if [ -z "$user_input" ]; then
            # Whiptail
            whiptail --clear --title "$TITLE" --msgbox "X11 keyboard layout is null" "$TUI_HEIGHT" "$TUI_WIDTH"
            ARCH_OS_X11_KEYBOARD_LAYOUT=""
            return 0
        fi
        ARCH_OS_X11_KEYBOARD_LAYOUT="$user_input"

        # Set X11 keyboard variant
        local user_input="$ARCH_OS_X11_KEYBOARD_VARIANT"
        [ -z "$user_input" ] && user_input=''
        user_input=$(whiptail --clear --title "$TITLE" --inputbox "\nEnter X11 (Xorg) keyboard variant\n\nExample: 'nodeadkeys' or leave empty for default" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$user_input" 3>&1 1>&2 2>&3)
        ARCH_OS_X11_KEYBOARD_VARIANT="$user_input"
    fi

    # Success
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////////////  MAIN  ////////////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# 1. START SETUP (TUI)

# Wait & sleep
wait && sleep 0.2

# Check dependencies
! command -v whiptail &>/dev/null && echo "ERROR: whiptail not installed" >&2 && exit 1
! command -v nano &>/dev/null && echo "ERROR: nano not installed" >&2 && exit 1
! command -v lsblk &>/dev/null && echo "ERROR: lsblk not installed" >&2 && exit 1

# Set error trap for setup
trap 'trap_error_setup ${LINENO} ${FUNCNAME-main}' ERR

# Print welcome screen
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
# SHOW SETUP MENU
# ----------------------------------------------------------------------------------------------------

while (true); do

    # Set default properties
    set_default_properties

    # Generate properties file if not exists (first start)
    [ ! -f "$CONFIG_FILE" ] && generate_properties_file

    # Source properties
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    # Check properties and set menu position
    check_properties || true

    # Create TUI menu entries
    menu_entry_array=()
    menu_entry_array+=("user") && menu_entry_array+=("$(print_menu_entry "User" "${ARCH_OS_USERNAME}")")
    menu_entry_array+=("password") && menu_entry_array+=("$(print_menu_entry "Password" "$([ -n "$ARCH_OS_PASSWORD" ] && echo "******")")")
    menu_entry_array+=("language") && menu_entry_array+=("$(print_menu_entry "Language" "${ARCH_OS_LOCALE_LANG}" "${ARCH_OS_TIMEZONE}")")
    menu_entry_array+=("keyboard") && menu_entry_array+=("$(print_menu_entry "Keyboard" "${ARCH_OS_VCONSOLE_KEYMAP}")")
    menu_entry_array+=("disk") && menu_entry_array+=("$(print_menu_entry "Disk" "${ARCH_OS_DISK}")")
    menu_entry_array+=("encrypt") && menu_entry_array+=("$(print_menu_entry "Encryption" "${ARCH_OS_ENCRYPTION_ENABLED}")")
    menu_entry_array+=("bootsplash") && menu_entry_array+=("$(print_menu_entry "Bootsplash" "${ARCH_OS_BOOTSPLASH_ENABLED}")")

    # Check if variant is set to desktop
    menu_variant="$ARCH_OS_VARIANT"
    [ "$menu_variant" = "desktop" ] && [ -z "${ARCH_OS_GRAPHICS_DRIVER}" ] && menu_variant=""
    [ "$menu_variant" = "desktop" ] && [ -z "${ARCH_OS_X11_KEYBOARD_LAYOUT}" ] && menu_variant=""
    menu_entry_array+=("variant") && menu_entry_array+=("$(print_menu_entry "Variant" "${menu_variant}")")

    # Empty entry
    menu_entry_array+=("") && menu_entry_array+=("")

    # Advanced config
    menu_entry_array+=("edit") && menu_entry_array+=("> Advanced Config")

    # Installation
    if [ "$TUI_POSITION" = "install" ]; then
        menu_entry_array+=("install") && menu_entry_array+=("> Continue Installation")
    else
        menu_entry_array+=("install") && menu_entry_array+=("x Continue Installation")
    fi

    # Open TUI menu
    #menu_selection=$(whiptail --clear --title "$TITLE" --menu "\n" --ok-button "Ok" --cancel-button "Exit" --notags --default-item "$TUI_POSITION" "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#menu_entry_array[@]} / 2) + (${#menu_entry_array[@]} % 2)))" "${menu_entry_array[@]}" 3>&1 1>&2 2>&3) || exit
    menu_selection=$(whiptail --clear --title "$TITLE" --menu "\n" --ok-button "Ok" --cancel-button "Exit" --notags --default-item "$TUI_POSITION" "$TUI_HEIGHT" "$TUI_WIDTH" "$((${#menu_entry_array[@]} / 2))" "${menu_entry_array[@]}" 3>&1 1>&2 2>&3) || exit

    # Handle result
    case "${menu_selection}" in

    "user")
        tui_set_user
        generate_properties_file
        ;;

    "password")
        tui_set_password
        generate_properties_file
        ;;

    "language")
        tui_set_language
        generate_properties_file
        ;;

    "keyboard")
        tui_set_keyboard
        generate_properties_file
        ;;

    "disk")
        tui_set_disk
        generate_properties_file
        ;;

    "encrypt")
        tui_set_encryption
        generate_properties_file
        ;;

    "bootsplash")
        tui_set_bootsplash
        generate_properties_file
        ;;

    "variant")
        tui_set_variant
        generate_properties_file
        ;;

    "edit")

        # Open config file in nano
        nano "$CONFIG_FILE" </dev/tty

        # Source may edited config
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"

        # Create config if something is missing after edit
        generate_properties_file
        ;;

    "install")

        # If install is pressed, but config is incomplete
        check_properties || continue

        # Ask for installation
        #if ! whiptail --clear --title "$TITLE" --yesno "Start Arch OS Linux Installation?\n\nAll data on ${ARCH_OS_DISK} will be DELETED!" --defaultno --yes-button "Start Installation" --no-button "Exit" "$TUI_HEIGHT" "$TUI_WIDTH"; then
        #    exit 1
        #fi

        ##########################################
        break # Break loop and start installation
        ##########################################
        ;;

    esac
done

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////////////  TUI END  /////////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////  ARCH OS CORE INSTALLATION  ////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# 2. START INSTALLATION

#./installer.sh "$ARCH_OS_PASSWORD" </dev/tty
source ./installer.sh

exit

# Messure execution time
SECONDS=0

# Set installation trap for error
trap 'trap_error_install ${LINENO} ${FUNCNAME-main}' ERR

# Set installation trap for logging on exit
trap 'trap_exit_install' EXIT

# Begin sub installation process (show whiptail gauge)
(
    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Arch OS Installation finished"
    # ----------------------------------------------------------------------------------------------------

    bash -c ./installer.sh "$ARCH_OS_PASSWORD"

) | whiptail --clear --title "$TITLE" --gauge "Start Arch OS Installation..." 7 "$TUI_WIDTH" 0

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////// ARCH OS INSTALLATION FINISHED ///////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Goto exit trap (see above)
exit 0
