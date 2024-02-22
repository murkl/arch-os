#!/usr/bin/env bash
export MODE="$1" # Start debug: ./installer.sh debug

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////// ARCH OS INSTALLER /////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# SOURCE:   https://github.com/murkl/arch-os
# AUTOR:    murkl
# ORIGIN:   Germany
# LICENCE:  GPL 2.0

# VERSION
VERSION='1.3.7'
GUM_VERSION="0.13.0"

# ENVIRONMENT
SCRIPT_CONF="./installer.conf"
SCRIPT_LOG="./installer.log"

# ERROR
ERROR_MSG="./installer.err"

# PROCESS
PROCESS_LOG="./process.log"
PROCESS_RETURN="./process.rt"

# COLORS
COLOR_WHITE=251
COLOR_GREEN=42
COLOR_PURPLE=212
COLOR_YELLOW=221
COLOR_RED=9

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Configuration
    set -o pipefail # A pipeline error results in the error status of the entire pipeline
    set -e          # Terminate if any command exits with a non-zero
    set -E          # ERR trap inherited by shell functions (errtrace)

    # Init
    rm -f "$SCRIPT_LOG"     # Clear logfile
    rm -f "$PROCESS_RETURN" # Clear process result file
    gum_init                # Check gum binary or download

    # Traps (error & exit)
    trap 'trap_exit' EXIT
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

    # Load existing config or remove
    if [ -f "$SCRIPT_CONF" ] && print_header && ! gum_confirm "Continue Installation?"; then
        gum_confirm "Remove existing properties?" || trap_gum_exit # If not want remove config, exit script
        rm -f "$SCRIPT_CONF"
    fi

    # Properties step begin...
    local first_run="true" # Set first run (skip edit on refresh)
    while (true); do       # Loop properties step to update screen if user edit properties

        # Print Welcome
        print_header && print_title "Welcome to Arch OS Installation"

        # Prepare properties
        properties_source   # Load properties file (if exists) and auto export variables
        properties_generate # Generate properties file (needed on first start of installer)

        # Selectors
        until select_username; do :; done
        until select_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_disk; do :; done
        until select_enable_encryption; do :; done
        until select_enable_bootsplash; do :; done
        until select_enable_multilib; do :; done
        until select_enable_aur; do :; done
        until select_enable_housekeeping; do :; done
        until select_enable_shell_enhancement; do :; done
        until select_enable_desktop; do :; done
        until select_enable_app; do :; done

        # Edit properties?
        if [ "$first_run" = "true" ] && gum_confirm "Edit Properties?"; then
            log_info "Edit properties..."
            local gum_header="Exit with CTRL + C and save with CTRL + D or ESC"
            if gum_write --height=10 --width=100 --header=" ${gum_header}" --value="$(cat "$SCRIPT_CONF")" >"${SCRIPT_CONF}.new"; then
                mv "${SCRIPT_CONF}.new" "${SCRIPT_CONF}" && properties_source
            fi
            rm -f "${SCRIPT_CONF}.new" # Remove tmp properties
            gum_confirm "Change Password?" && until select_password --force; do :; done
            first_run="false" && continue # Restart properties step to refresh log above if changed
        fi

        print_info "Properties successfully initialized"
        break # Exit properties step and continue installation
    done

    # Start installation in 5 seconds?
    gum_confirm "Start Arch OS Installation?" || trap_gum_exit
    local spin_title="Arch OS Installation starts in 5 seconds. Press CTRL + C to cancel..."
    gum_spin --title=" $spin_title" -- sleep 5 || trap_gum_exit # CTRL + C pressed
    print_info "Arch OS Installation starts..."

    SECONDS=0 # Messure execution time of installation

    # Executors
    exec_init_installation
    exec_prepare_disk
    exec_pacstrap_core
    exec_enable_multilib
    exec_install_bootsplash
    exec_install_aur_helper
    exec_install_housekeeping
    exec_install_shell_enhancement
    exec_install_desktop
    exec_install_graphics_driver
    exec_install_vm_support
    exec_install_app
    exec_cleanup_installation

    # Calc installation duration
    duration=$SECONDS # This is set before install starts
    duration_min="$((duration / 60))"
    duration_sec="$((duration % 60))"

    # Finish & reboot
    print_info "Installation successful in ${duration_min} minutes and ${duration_sec} seconds"
    gum_confirm "Reboot to Arch OS now?" && print_warn "Rebooting..." && [ "$MODE" != "debug" ] && reboot
    exit 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM
# ////////////////////////////////////////////////////////////////////////////////////////////////////

gum_init() {
    if [ ! -x ./gum ] && ! command -v /usr/bin/gum &>/dev/null; then
        clear && echo "Loading Arch OS Installer..." # Loading
        local gum_cache="${HOME}/.cache/arch-os-gum" # Cache dir
        rm -rf "$gum_cache"                          # Clean cache dir
        if ! mkdir -p "$gum_cache"; then echo "Error creating ${gum_cache}" && exit 1; fi
        local gum_url # Prepare URL with version os and arch
        # https://github.com/charmbracelet/gum/releases
        gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_$(uname -s)_$(uname -m).tar.gz"
        if ! curl -Lsf "$gum_url" >"${gum_cache}/gum.tar.gz"; then echo "Error downloading ${gum_url}" && exit 1; fi
        if ! tar -xf "${gum_cache}/gum.tar.gz" --directory "$gum_cache"; then echo "Error extracting ${gum_cache}/gum.tar.gz" && exit 1; fi
        if ! mv "${gum_cache}/gum" ./gum; then echo "Error moving ${gum_cache}/gum to ./gum" && exit 1; fi
        if ! chmod +x ./gum; then echo "Error chmod +x ./gum" && exit 1; fi
        rm -rf "$gum_cache" # # Clean cache dir
    fi
}

gum() {
    if [ -x ./gum ]; then ./gum "$@"; else /usr/bin/gum "$@"; fi # Force open ./gum if exists
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# TRAPS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# shellcheck disable=SC2317
trap_error() {
    # If process calls this trap, write error to file to use in exit trap
    echo "Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})" >"$ERROR_MSG"
}

# shellcheck disable=SC2317
trap_exit() {
    local result_code="$?"

    # Read error msg from file (written in error trap)
    local error && [ -f "$ERROR_MSG" ] && error="$(<"$ERROR_MSG")" && rm -f "$ERROR_MSG"

    # Remove files
    rm -f "$PROCESS_RETURN" # Remove process return info
    rm -f "$PROCESS_LOG"    # Remove prcoess log

    # When ctrl + c pressed exit without other stuff below
    [ "$result_code" = "130" ] && print_warn "Exit..." && exit 1

    # Check if failed and print error
    if [ "$result_code" -gt "0" ]; then
        [ -n "$error" ] && print_fail "$error"                                   # Print error message (if exists)
        [ -z "$error" ] && print_fail "Arch OS Installation failed"              # Otherwise pint default error message
        gum_confirm "Show Logs?" && gum_pager --show-line-numbers <"$SCRIPT_LOG" # Ask for show logs?
    fi

    exit "$result_code" # Exit installer.sh
}

trap_gum_exit_confirm() {
    gum_confirm "Exit Installation?" && trap_gum_exit
}

trap_gum_exit() { exit 130; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    [ -f "$PROCESS_RETURN" ] && print_fail "${PROCESS_RETURN} already exists" && exit 1
    echo 1 >"$PROCESS_RETURN" # Init result with 1
    log_proc "${1}..."        # Log starting
}

process_run() {
    local pid="$1"              # Set process pid
    local process_name="$2"     # Set process name
    local user_canceled="false" # Will set to true if user press ctrl + c

    # Show gum spinner until pid is not exists anymore and set user_canceled to true on failure
    gum_spin --title " ${process_name}..." -- bash -c "while kill -0 $pid &> /dev/null; do sleep 1; done" || user_canceled="true"
    cat "$PROCESS_LOG" >>"$SCRIPT_LOG" # Write process log to logfile

    # When user press ctrl + c while process is running
    if [ "$user_canceled" = "true" ]; then
        kill -0 "$pid" &>/dev/null && pkill -P "$pid"                            # Kill process if running
        print_fail "Process with PID ${pid} was killed by user" && trap_gum_exit # Exit with 130
    fi

    # Handle error while executing process
    [ ! -f "$PROCESS_RETURN" ] && print_fail "${PROCESS_RETURN} not found (do not init process?)" && exit 1
    [ "$(<"$PROCESS_RETURN")" != "0" ] && print_fail "${process_name} failed" && exit 1 # If process failed (result code 0 was not write in the end)

    # Finish
    rm -f "$PROCESS_RETURN"                          # Remove process result file
    print_add "${process_name} sucessfully finished" # Print process success
}

process_return() {
    # 1. Write from sub process 0 to file when succeed (at the end of the script part)
    # 2. Rread from parent process after sub process finished (0=success 1=failed)
    echo "$1" >"$PROCESS_RETURN"
    exit "$1"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOG & PRINT
# ////////////////////////////////////////////////////////////////////////////////////////////////////

print_header() {
    local header_logo header_title header_container
    header_logo='
 █████  ██████   ██████ ██   ██      ██████  ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
███████ ██████  ██      ███████     ██    ██ ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
██   ██ ██   ██  ██████ ██   ██      ██████  ███████
    ' && header_logo=$(gum_purple --bold "$header_logo")
    header_title="Arch OS Installer ${VERSION}" && header_title=$(gum_white --bold "$header_title")
    header_container=$(gum join --vertical --align center "$header_logo" "$header_title")
    clear && gum_style --padding "0 1" "$header_container"
}

# Log
write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }

# Print
print_title() { gum_purple --margin "1 1" --bold "${*}"; }
print_info() { log_info "$*" && gum_green --bold " • ${*}"; }
print_warn() { log_warn "$*" && gum_yellow --bold " • ${*}"; }
print_fail() { log_fail "$*" && gum_red --bold " • ${*}"; }
print_add() { log_info "$*" && gum_green --bold " + ${*}"; }

# Colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }
gum_purple() { gum_style --foreground "$COLOR_PURPLE" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }

# Gum
gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_PURPLE" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt " + " --prompt.foreground "$COLOR_PURPLE" --header.foreground "$COLOR_PURPLE" "${@}"; }
gum_write() { gum write --prompt " • " --header.foreground "$COLOR_PURPLE" --show-cursor-line --char-limit 0 "${@}"; }
gum_choose() { gum choose --cursor " > " --header.foreground "$COLOR_PURPLE" --cursor.foreground "$COLOR_PURPLE" "${@}"; }
gum_filter() { gum filter --prompt " > " --indicator " • " --placeholder "Type to filter ..." --height 8 --header.foreground "$COLOR_PURPLE" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_PURPLE" --spinner.foreground "$COLOR_PURPLE" "${@}"; }
# shellcheck disable=SC2317
gum_pager() { gum pager "${@}"; } # Only used in exit trap

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROPERTIES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# shellcheck disable=SC1090
properties_source() {
    if [ -f "$SCRIPT_CONF" ]; then
        set -a # Enable auto export of variables
        source "$SCRIPT_CONF"
        set +a # Disable auto export of variables
    fi
}

properties_generate() {
    # Set defaults
    [ -z "$ARCH_OS_HOSTNAME" ] && ARCH_OS_HOSTNAME="arch-os"
    [ -z "$ARCH_OS_KERNEL" ] && ARCH_OS_KERNEL="linux-zen"
    [ -z "$ARCH_OS_VM_SUPPORT_ENABLED" ] && ARCH_OS_VM_SUPPORT_ENABLED="true"
    [ -z "$ARCH_OS_ECN_ENABLED" ] && ARCH_OS_ECN_ENABLED="true"
    [ -z "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" ] && ARCH_OS_DESKTOP_GRAPHICS_DRIVER="none"
    [ -z "$ARCH_OS_DESKTOP_KEYBOARD_MODEL" ] && ARCH_OS_DESKTOP_KEYBOARD_MODEL="pc105"
    [ -z "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" ] && ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="us"
    [ -z "$ARCH_OS_MICROCODE" ] && grep -E "GenuineIntel" &>/dev/null <<<"$(lscpu) " && ARCH_OS_MICROCODE="intel-ucode"
    [ -z "$ARCH_OS_MICROCODE" ] && grep -E "AuthenticAMD" &>/dev/null <<<"$(lscpu)" && ARCH_OS_MICROCODE="amd-ucode"
    { # Write properties to installer.conf
        #echo "# Arch OS ${VERSION} ($(date --utc '+%Y-%m-%d %H:%M:%S') UTC)"
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
        echo "ARCH_OS_DESKTOP_ENABLED='${ARCH_OS_DESKTOP_ENABLED}'"
        echo "ARCH_OS_APP_ENABLED='${ARCH_OS_APP_ENABLED}'"
        echo "ARCH_OS_SHELL_ENHANCEMENT_ENABLED='${ARCH_OS_SHELL_ENHANCEMENT_ENABLED}'"
        echo "ARCH_OS_AUR_HELPER='${ARCH_OS_AUR_HELPER}'"
        echo "ARCH_OS_MULTILIB_ENABLED='${ARCH_OS_MULTILIB_ENABLED}'"
        echo "ARCH_OS_HOUSEKEEPING_ENABLED='${ARCH_OS_HOUSEKEEPING_ENABLED}'"
        echo "ARCH_OS_REFLECTOR_COUNTRY='${ARCH_OS_REFLECTOR_COUNTRY}'"
        echo "ARCH_OS_DESKTOP_GRAPHICS_DRIVER='${ARCH_OS_DESKTOP_GRAPHICS_DRIVER}'"
        echo "ARCH_OS_DESKTOP_KEYBOARD_LAYOUT='${ARCH_OS_DESKTOP_KEYBOARD_LAYOUT}'"
        echo "ARCH_OS_DESKTOP_KEYBOARD_MODEL='${ARCH_OS_DESKTOP_KEYBOARD_MODEL}'"
        echo "ARCH_OS_DESKTOP_KEYBOARD_VARIANT='${ARCH_OS_DESKTOP_KEYBOARD_VARIANT}'"
        echo "ARCH_OS_VM_SUPPORT_ENABLED='${ARCH_OS_VM_SUPPORT_ENABLED}'"
    } >"$SCRIPT_CONF" # Write properties to file
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_username() {
    if [ -z "$ARCH_OS_USERNAME" ]; then
        local user_input
        user_input=$(gum_input --header " + Enter Username") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                      # Check if new value is null
        ARCH_OS_USERNAME="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Username is set to ${ARCH_OS_USERNAME}"
}

# ----------------------------------------------------------------------------------------------------

select_password() { # --force
    if [ "$1" = "--force" ] || [ -z "$ARCH_OS_PASSWORD" ]; then
        local user_password user_password_check
        user_password=$(gum_input --password --header " + Enter Password") || trap_gum_exit_confirm
        [ -z "$user_password" ] && return 1 # Check if new value is null
        user_password_check=$(gum_input --password --header " + Enter Password again") || trap_gum_exit_confirm
        [ -z "$user_password_check" ] && return 1 # Check if new value is null
        [ "$user_password" != "$user_password_check" ] && print_fail "Passwords not identical" && return 1
        ARCH_OS_PASSWORD="$user_password" && properties_generate # Set value and generate properties file
    fi
    print_add "Password is set to *******"
}

# ----------------------------------------------------------------------------------------------------

select_timezone() {
    if [ -z "$ARCH_OS_TIMEZONE" ]; then
        local tz_auto user_input
        tz_auto="$(curl -s http://ip-api.com/line?fields=timezone)"
        user_input=$(gum_input --header " + Enter Timezone (auto)" --value "$tz_auto") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        [ ! -f "/usr/share/zoneinfo/${user_input}" ] && print_fail "Timezone '${user_input}' is not supported" && return 1
        ARCH_OS_TIMEZONE="$user_input" && properties_generate # Set property and generate properties file
    fi
    print_add "Timezone is set to ${ARCH_OS_TIMEZONE}"
}

# ----------------------------------------------------------------------------------------------------

# shellcheck disable=SC2001
select_language() {
    if [ -z "$ARCH_OS_LOCALE_LANG" ] || [ -z "${ARCH_OS_LOCALE_GEN_LIST[*]}" ]; then
        local user_input items options
        # Fetch available options (list all from /usr/share/i18n/locales and check if entry exists in /etc/locale.gen)
        mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@") # Create array without @ files
        # Add only available locales (!!! intense command !!!)
        options=() && for item in "${items[@]}"; do grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
        # Select locale
        user_input=$(gum_filter --header " + Choose Language" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1  # Check if new value is null
        ARCH_OS_LOCALE_LANG="$user_input" # Set property
        # Set locale.gen properties (auto generate ARCH_OS_LOCALE_GEN_LIST)
        ARCH_OS_LOCALE_GEN_LIST=() && while read -r locale_entry; do
            ARCH_OS_LOCALE_GEN_LIST+=("$locale_entry")
        done < <(sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "$ARCH_OS_LOCALE_LANG")
        # Add en_US fallback (every language)
        [[ "${ARCH_OS_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && ARCH_OS_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')
        properties_generate # Generate properties file (for ARCH_OS_LOCALE_LANG & ARCH_OS_LOCALE_GEN_LIST)
    fi
    print_add "Language is set to ${ARCH_OS_LOCALE_LANG}"
}

# ----------------------------------------------------------------------------------------------------

select_keyboard() {
    if [ -z "$ARCH_OS_VCONSOLE_KEYMAP" ]; then
        local user_input items options
        mapfile -t items < <(command localectl list-keymaps)
        options=() && for item in "${items[@]}"; do options+=("$item"); done
        user_input=$(gum_filter --header " + Choose Keyboard" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                             # Check if new value is null
        ARCH_OS_VCONSOLE_KEYMAP="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Keyboard is set to ${ARCH_OS_VCONSOLE_KEYMAP}"
}

# ----------------------------------------------------------------------------------------------------

select_disk() {
    if [ -z "$ARCH_OS_DISK" ] || [ -z "$ARCH_OS_BOOT_PARTITION" ] || [ -z "$ARCH_OS_ROOT_PARTITION" ]; then
        local user_input items options
        mapfile -t items < <(lsblk -I 8,259,254 -d -o KNAME -n)
        # size: $(lsblk -d -n -o SIZE "/dev/${item}")
        options=() && for item in "${items[@]}"; do options+=("/dev/${item}"); done
        user_input=$(gum_choose --header " + Choose Disk" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        [ ! -e "$user_input" ] && log_fail "Disk does not exists" && return 1
        ARCH_OS_DISK="$user_input" # Set property
        [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}p1" || ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}1"
        [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}p2" || ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}2"
        properties_generate # Generate properties file
    fi
    print_add "Disk is set to ${ARCH_OS_DISK}"
}

# ----------------------------------------------------------------------------------------------------

select_enable_encryption() {
    if [ -z "$ARCH_OS_ENCRYPTION_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable Disk Encryption?" && user_input="true"
        ARCH_OS_ENCRYPTION_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Disk Encryption is set to ${ARCH_OS_ENCRYPTION_ENABLED}"
}

# ----------------------------------------------------------------------------------------------------

select_enable_bootsplash() {
    if [ -z "$ARCH_OS_BOOTSPLASH_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable Bootsplash?" && user_input="true"
        ARCH_OS_BOOTSPLASH_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Bootsplash is set to ${ARCH_OS_BOOTSPLASH_ENABLED}"
}

# ----------------------------------------------------------------------------------------------------

select_enable_desktop() {
    if [ -z "$ARCH_OS_DESKTOP_ENABLED" ] || [ -z "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" ] || [ -z "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" ]; then
        local user_input options
        user_input="false" && gum_confirm "Enable Arch OS Desktop?" && user_input="true"
        ARCH_OS_DESKTOP_ENABLED="$user_input"            # Set property
        if [ "$ARCH_OS_DESKTOP_ENABLED" = "true" ]; then # If desktop is true set graphics driver and keyboard layout
            options=("mesa" "intel_i915" "nvidia" "amd" "ati")
            user_input=$(gum_choose --header " + Choose Desktop Graphics Driver" "${options[@]}") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1              # Check if new value is null
            ARCH_OS_DESKTOP_GRAPHICS_DRIVER="$user_input" # Set property
            user_input=$(gum_input --header " + Enter Desktop Keyboard Layout" --value "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1              # Check if new value is null
            ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="$user_input" # Set property
        fi
        properties_generate # Generate properties file
    fi
    print_add "Arch OS Desktop is set to ${ARCH_OS_DESKTOP_ENABLED}"
    [ "$ARCH_OS_DESKTOP_ENABLED" = "true" ] && print_add "Desktop Keyboard Layout is set to ${ARCH_OS_DESKTOP_KEYBOARD_LAYOUT}"
    [ "$ARCH_OS_DESKTOP_ENABLED" = "true" ] && print_add "Desktop Graphics Driver is set to ${ARCH_OS_DESKTOP_GRAPHICS_DRIVER}"
    return 0
}

# ----------------------------------------------------------------------------------------------------

select_enable_aur() {
    if [ -z "$ARCH_OS_AUR_HELPER" ]; then
        local user_input="none" && gum_confirm "Enable AUR Helper?" && user_input="paru"
        ARCH_OS_AUR_HELPER="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "AUR Helper is set to ${ARCH_OS_AUR_HELPER}"
}

# ----------------------------------------------------------------------------------------------------

select_enable_multilib() {
    if [ -z "$ARCH_OS_MULTILIB_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable 32 Bit Support?" && user_input="true"
        ARCH_OS_MULTILIB_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "32 Bit Support is set to ${ARCH_OS_MULTILIB_ENABLED}"
}

# ----------------------------------------------------------------------------------------------------

select_enable_housekeeping() {
    if [ -z "$ARCH_OS_HOUSEKEEPING_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable Housekeeping?" && user_input="true"
        ARCH_OS_HOUSEKEEPING_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Housekeeping is set to ${ARCH_OS_HOUSEKEEPING_ENABLED}"
}

# ----------------------------------------------------------------------------------------------------

select_enable_shell_enhancement() {
    if [ -z "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable Shell Enhancement?" && user_input="true"
        ARCH_OS_SHELL_ENHANCEMENT_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Shell Enhancement is set to ${ARCH_OS_SHELL_ENHANCEMENT_ENABLED}"
}

# ----------------------------------------------------------------------------------------------------

select_enable_app() {
    if [ -z "$ARCH_OS_APP_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable Arch OS App?" && user_input="true"
        ARCH_OS_APP_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Arch OS App is set to ${ARCH_OS_APP_ENABLED}"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# CHROOT HELPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

chroot_pacman_install() {
    local packages=("$@")
    local pacman_failed="true"
    # Retry installing packages 5 times (in case of connection issues)
    for ((i = 1; i < 6; i++)); do
        # Print updated whiptail info
        [ "$i" -gt 1 ] && log_warn "${i}. Retry Pacman installation..."
        # Try installing packages
        if ! arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"; then
            sleep 10 && continue # Wait 10 seconds & try again
        else
            pacman_failed="false" && break # Success: break loop
        fi
    done
    # Result
    [ "$pacman_failed" = "true" ] && return 1  # Failed after 5 retries
    [ "$pacman_failed" = "false" ] && return 0 # Success
}

# ----------------------------------------------------------------------------------------------------

chroot_aur_install() {
    local repo repo_url repo_tmp_dir
    repo="$1"
    repo_url="https://aur.archlinux.org/${repo}.git"
    repo_tmp_dir=$(mktemp -u "/home/${ARCH_OS_USERNAME}/${repo}.XXXXXXXXXX")
    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers # Disable sudo needs no password rights
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git clone "$repo_url" "$repo_tmp_dir"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "cd $repo_tmp_dir && makepkg -si --noconfirm"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- rm -rf "$repo_tmp_dir"
    sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers # Enable sudo needs no password rights
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# EXECUTORS (SUB PROCESSES)
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init_installation() {
    local process_name="Initialize Installation"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return
        # Check installation prerequisites
        [ ! -d /sys/firmware/efi ] && log_fail "BIOS not supported! Please set your boot mode to UEFI." && exit 1
        log_info "UEFI detected"
        [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && log_fail "You must execute the Installer from Arch ISO!" && exit 1
        log_info "Waiting for Reflector from Arch ISO"
        # This mirrorlist will copied to new Arch system during installation
        while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
        pgrep reflector &>/dev/null && log_fail "Reflector timeout after 180 seconds" && exit 1
        timedatectl set-ntp true # Set time
        # Make sure everything is unmounted before start install
        swapoff -a &>/dev/null || true
        umount -A -R /mnt &>/dev/null || true
        cryptsetup close cryptroot &>/dev/null || true
        vgchange -an || true
        # Temporarily disable ECN (prevent traffic problems with some old routers)
        [ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0
        pacman -Sy --noconfirm archlinux-keyring # Update keyring
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_prepare_disk() {
    local process_name="Prepare Disk"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return

        # Wipe and create partitions
        wipefs -af "$ARCH_OS_DISK"                            # Wipe all partitions
        sgdisk -o "$ARCH_OS_DISK"                             # Create new GPT partition table
        sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot "$ARCH_OS_DISK" # Create partition /boot efi partition: 1 GiB
        sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$ARCH_OS_DISK"   # Create partition / partition: Rest of space
        partprobe "$ARCH_OS_DISK"                             # Reload partition table

        # Disk encryption
        if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
            log_info "Enable Disk Encryption for ${ARCH_OS_ROOT_PARTITION}"
            echo -n "$ARCH_OS_PASSWORD" | cryptsetup luksFormat "$ARCH_OS_ROOT_PARTITION"
            echo -n "$ARCH_OS_PASSWORD" | cryptsetup open "$ARCH_OS_ROOT_PARTITION" cryptroot
        fi

        # Format disk
        mkfs.fat -F 32 -n BOOT "$ARCH_OS_BOOT_PARTITION"
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && mkfs.ext4 -F -L ROOT /dev/mapper/cryptroot
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && mkfs.ext4 -F -L ROOT "$ARCH_OS_ROOT_PARTITION"

        # Mount disk to /mnt
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && mount -v /dev/mapper/cryptroot /mnt
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && mount -v "$ARCH_OS_ROOT_PARTITION" /mnt
        mkdir -p /mnt/boot
        mount -v "$ARCH_OS_BOOT_PARTITION" /mnt/boot

        # Return
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_pacstrap_core() {
    local process_name="Pacstrap Arch OS Core System"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return

        # Minimal Core packages
        local packages=("$ARCH_OS_KERNEL" base sudo linux-firmware zram-generator networkmanager)

        # Add microcode package
        [ -n "$ARCH_OS_MICROCODE" ] && [ "$ARCH_OS_MICROCODE" != "none" ] && packages+=("$ARCH_OS_MICROCODE")

        # Install core packages and initialize an empty pacman keyring in the target
        pacstrap -K /mnt "${packages[@]}"

        # Generate /etc/fstab
        genfstab -U /mnt >>/mnt/etc/fstab

        # Set timezone & system clock
        arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${ARCH_OS_TIMEZONE}" /etc/localtime
        arch-chroot /mnt hwclock --systohc # Set hardware clock from system clock

        # Create swap (zram-generator with zstd compression)
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

        # Set console keymap in /etc/vconsole.conf
        echo "KEYMAP=$ARCH_OS_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf
        [ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=$ARCH_OS_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf

        # Set & Generate Locale
        echo "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" >/mnt/etc/locale.conf
        for ((i = 0; i < ${#ARCH_OS_LOCALE_GEN_LIST[@]}; i++)); do sed -i "s/^#${ARCH_OS_LOCALE_GEN_LIST[$i]}/${ARCH_OS_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen"; done
        arch-chroot /mnt locale-gen

        # Set hostname & hosts
        echo "$ARCH_OS_HOSTNAME" >/mnt/etc/hostname
        {
            echo '127.0.0.1    localhost'
            echo '::1          localhost'
        } >/mnt/etc/hosts

        # Create initial ramdisk from /etc/mkinitcpio.conf
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect modconf block sd-encrypt filesystems sd-vconsole fsck)/" /mnt/etc/mkinitcpio.conf
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect modconf block filesystems sd-vconsole fsck)/" /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P

        # Install Bootloader to /boot (systemdboot)
        arch-chroot /mnt bootctl --esp-path=/boot install # Install systemdboot to /boot

        # Kernel args
        # Zswap should be disabled when using zram (https://github.com/archlinux/archinstall/issues/881)
        kernel_args_default="rw init=/usr/lib/systemd/systemd zswap.enabled=0 modprobe.blacklist=iTCO_wdt nowatchdog quiet splash vt.global_cursor_default=0"
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
            [ -n "$ARCH_OS_MICROCODE" ] && [ "$ARCH_OS_MICROCODE" != "none" ] && echo "initrd  /${ARCH_OS_MICROCODE}.img"
            echo "initrd  /initramfs-${ARCH_OS_KERNEL}.img"
            echo "options ${kernel_args}"
        } >/mnt/boot/loader/entries/arch.conf

        # Create fallback boot entry
        {
            echo 'title   Arch OS (Fallback)'
            echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
            [ -n "$ARCH_OS_MICROCODE" ] && [ "$ARCH_OS_MICROCODE" != "none" ] && echo "initrd  /${ARCH_OS_MICROCODE}.img"
            echo "initrd  /initramfs-${ARCH_OS_KERNEL}-fallback.img"
            echo "options ${kernel_args}"
        } >/mnt/boot/loader/entries/arch-fallback.conf

        # Create new user
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"

        # Allow users in group wheel to use sudo
        sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers

        # Add password feedback
        echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers

        # Change passwords
        printf "%s\n%s" "${ARCH_OS_PASSWORD}" "${ARCH_OS_PASSWORD}" | arch-chroot /mnt passwd
        printf "%s\n%s" "${ARCH_OS_PASSWORD}" "${ARCH_OS_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_OS_USERNAME"

        # Enable services
        arch-chroot /mnt systemctl enable NetworkManager                   # Network Manager
        arch-chroot /mnt systemctl enable fstrim.timer                     # SSD support
        arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service # Swap (zram-generator)
        arch-chroot /mnt systemctl enable systemd-oomd.service             # Out of memory killer (swap is required)
        arch-chroot /mnt systemctl enable systemd-boot-update.service      # Auto bootloader update
        arch-chroot /mnt systemctl enable systemd-timesyncd.service        # Sync time from internet after boot

        # Reduce shutdown timeout
        sed -i "s/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf

        # Set max VMAs (need for some apps/games)
        echo vm.max_map_count=1048576 >/mnt/etc/sysctl.d/vm.max_map_count.conf

        # Configure pacman parrallel downloads, colors, eyecandy
        sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
        sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf

        # Return
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_install_desktop() {
    local process_name="Install Arch OS Desktop System"
    if [ "$ARCH_OS_DESKTOP_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return

            # GNOME base packages
            local packages=(gnome gnome-tweaks gnome-browser-connector gnome-themes-extra gnome-firmware power-profiles-daemon fwupd rygel cups)

            # GNOME wayland screensharing, flatpak & pipewire support
            packages+=(xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome)

            # Audio (Pipewire replacements + session manager)
            packages+=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber)
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

            # Networking & Access
            packages+=(samba gvfs gvfs-mtp gvfs-smb gvfs-nfs gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-google)

            # Utils (https://wiki.archlinux.org/title/File_systems)
            packages+=(git nfs-utils f2fs-tools udftools dosfstools ntfs-3g exfat-utils p7zip zip unzip unrar tar)

            # Codecs
            packages+=(gstreamer gst-libav gst-plugin-pipewire gst-plugins-ugly libdvdcss libheif webp-pixbuf-loader)
            packages+=(a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore libdvdnav fuse-exfat libdvdread)
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gstreamer)

            # Optimization
            packages+=(gamemode)
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

            # Fonts
            packages+=(noto-fonts noto-fonts-emoji ttf-firacode-nerd ttf-liberation ttf-dejavu)

            # Install packages
            chroot_pacman_install "${packages[@]}"

            # Add user to gamemode group
            arch-chroot /mnt gpasswd -a "$ARCH_OS_USERNAME" gamemode

            # Enable GNOME auto login
            grep -qrnw /mnt/etc/gdm/custom.conf -e "AutomaticLoginEnable" || sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${ARCH_OS_USERNAME}\n\n\[security\]/g" /mnt/etc/gdm/custom.conf

            # Set git-credential-libsecret in ~/.gitconfig
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git config --global credential.helper /usr/lib/git-core/git-credential-libsecret

            # GnuPG integration (https://wiki.archlinux.org/title/GNOME/Keyring#GnuPG_integration)
            mkdir -p "/mnt/home/${ARCH_OS_USERNAME}/.gnupg"
            echo 'pinentry-program /usr/bin/pinentry-gnome3' >"/mnt/home/${ARCH_OS_USERNAME}/.gnupg/gpg-agent.conf"

            # Set environment
            mkdir -p "/mnt/home/${ARCH_OS_USERNAME}/.config/environment.d/"
            # shellcheck disable=SC2016
            {
                echo '# SSH AGENT'
                echo 'SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh' # Set gcr sock (https://wiki.archlinux.org/title/GNOME/Keyring#Setup_gcr)
                echo ''
                echo '# PATH'
                echo 'PATH="${PATH}:${HOME}/.local/bin"'
                echo ''
                echo '# XDG'
                echo 'XDG_CONFIG_HOME="${HOME}/.config"'
                echo 'XDG_DATA_HOME="${HOME}/.local/share"'
                echo 'XDG_STATE_HOME="${HOME}/.local/state"'
                echo 'XDG_CACHE_HOME="${HOME}/.cache"                '
            } >"/mnt/home/${ARCH_OS_USERNAME}/.config/environment.d/00-arch-os.conf"

            # Samba
            mkdir -p "/mnt/etc/samba/"
            {
                echo "[global]"
                echo "   workgroup = WORKGROUP"
                echo "   log file = /var/log/samba/%m"
            } >/mnt/etc/samba/smb.conf

            # Set X11 keyboard layout in /etc/X11/xorg.conf.d/00-keyboard.conf
            {
                echo 'Section "InputClass"'
                echo '    Identifier "system-keyboard"'
                echo '    MatchIsKeyboard "yes"'
                echo '    Option "XkbLayout" "'"${ARCH_OS_DESKTOP_KEYBOARD_LAYOUT}"'"'
                echo '    Option "XkbModel" "'"${ARCH_OS_DESKTOP_KEYBOARD_MODEL}"'"'
                echo '    Option "XkbVariant" "'"${ARCH_OS_DESKTOP_KEYBOARD_VARIANT}"'"'
                echo 'EndSection'
            } >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf

            # Enable Arch OS Desktop services
            arch-chroot /mnt systemctl enable gdm.service                                                              # GNOME
            arch-chroot /mnt systemctl enable bluetooth.service                                                        # Bluetooth
            arch-chroot /mnt systemctl enable avahi-daemon                                                             # Network browsing service
            arch-chroot /mnt systemctl enable cups.socket                                                              # Printer
            arch-chroot /mnt systemctl enable smb.service                                                              # Samba
            arch-chroot /mnt systemctl enable nmb.service                                                              # Samba
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire.service       # Pipewire
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire-pulse.service # Pipewire
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user wireplumber.service    # Pipewire
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user gcr-ssh-agent.socket   # GCR ssh-agent

            # Hide desktop Aaplications icons
            mkdir -p "/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/bssh.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/bvnc.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/avahi-discover.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/qv4l2.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/qvidcap.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/lstopo.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/cups.desktop"

            # Hide Shell Enhancement apps
            if [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/fish.desktop"
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/btop.desktop"
            fi

            # Hide Kitty app
            if [ "$ARCH_OS_APP_ENABLED" = "true" ]; then
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/kitty.desktop"
            fi

            # Set correct permissions
            arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"

            # Return
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_install_graphics_driver() {
    local process_name="Install Graphics Driver"
    if [ -n "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" ] && [ "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" != "none" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return
            case "${ARCH_OS_DESKTOP_GRAPHICS_DRIVER}" in
            "mesa") # https://wiki.archlinux.org/title/OpenGL#Installation
                local packages=(mesa mesa-utils vkd3d)
                [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-mesa-utils lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                ;;
            "intel_i915") # https://wiki.archlinux.org/title/Intel_graphics#Installation
                local packages=(vulkan-intel vkd3d libva-intel-driver)
                [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-vulkan-intel lib32-vkd3d lib32-libva-intel-driver)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "nvidia") # https://wiki.archlinux.org/title/NVIDIA#Installation
                local packages=("${ARCH_OS_KERNEL}-headers" nvidia-dkms nvidia-settings nvidia-utils opencl-nvidia vkd3d)
                [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-nvidia-utils lib32-opencl-nvidia lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
                # Alternative (slow boot, bios logo twice, but correct plymouth resolution):
                #sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 nvidia_drm.fbdev=1 quiet/g" /mnt/boot/loader/entries/arch.conf
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
                local packages=(xf86-video-amdgpu libva-mesa-driver vulkan-radeon mesa-vdpau vkd3d)
                [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-libva-mesa-driver lib32-vulkan-radeon lib32-mesa-vdpau lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # Must be discussed: https://wiki.archlinux.org/title/AMDGPU#Disable_loading_radeon_completely_at_boot
                sed -i "s/^MODULES=(.*)/MODULES=(amdgpu radeon)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "ati") # https://wiki.archlinux.org/title/ATI#Installation
                local packages=(xf86-video-ati libva-mesa-driver mesa-vdpau vkd3d)
                [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-libva-mesa-driver lib32-mesa-vdpau lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            esac
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_install_vm_support() {
    local process_name="Install VM Support"
    if [ "$ARCH_OS_VM_SUPPORT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return
            case $(systemd-detect-virt || true) in
            kvm)
                log_info "KVM detected"
                chroot_pacman_install spice spice-vdagent spice-protocol spice-gtk qemu-guest-agent
                arch-chroot /mnt systemctl enable qemu-guest-agent
                ;;
            vmware)
                log_info "VMWare Workstation/ESXi detected"
                chroot_pacman_install open-vm-tools
                arch-chroot /mnt systemctl enable vmtoolsd
                arch-chroot /mnt systemctl enable vmware-vmblock-fuse
                ;;
            oracle)
                log_info "VirtualBox detected"
                chroot_pacman_install virtualbox-guest-utils
                arch-chroot /mnt systemctl enable vboxservice
                ;;
            microsoft)
                log_info "Hyper-V detected"
                chroot_pacman_install hyperv
                arch-chroot /mnt systemctl enable hv_fcopy_daemon
                arch-chroot /mnt systemctl enable hv_kvp_daemon
                arch-chroot /mnt systemctl enable hv_vss_daemon
                ;;
            *) log_info "No VM detected" ;; # Do nothing
            esac
            process_return 0 # Return
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_install_bootsplash() {
    local process_name="Install Bootsplash"
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0                                       # If debug mode then return
            chroot_pacman_install plymouth git base-devel                                              # Install packages
            sed -i "s/base systemd keyboard/base systemd plymouth keyboard/g" /mnt/etc/mkinitcpio.conf # Configure mkinitcpio
            chroot_aur_install plymouth-theme-arch-os                                                  # Install Arch OS plymouth theme from AUR
            arch-chroot /mnt plymouth-set-default-theme -R arch-os                                     # Set Theme & rebuild initram disk
            process_return 0                                                                           # Return
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_install_aur_helper() {
    local process_name="Install AUR Helper"
    if [ -n "$ARCH_OS_AUR_HELPER" ] && [ "$ARCH_OS_AUR_HELPER" != "none" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return
            chroot_pacman_install git base-devel                 # Install packages
            chroot_aur_install "$ARCH_OS_AUR_HELPER"             # Install AUR helper
            # Paru config
            if [ "$ARCH_OS_AUR_HELPER" = "paru" ] || [ "$ARCH_OS_AUR_HELPER" = "paru-bin" ] || [ "$ARCH_OS_AUR_HELPER" = "paru-git" ]; then
                sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf
                sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf
            fi
            process_return 0 # Return
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_enable_multilib() {
    local process_name="Enable Multilib"
    if [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return
            sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
            arch-chroot /mnt pacman -Syyu --noconfirm
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_install_housekeeping() {
    local process_name="Install Housekeeping"
    if [ "$ARCH_OS_HOUSEKEEPING_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0   # If debug mode then return
            chroot_pacman_install pacman-contrib reflector pkgfile # Install Base packages
            {                                                      # Configure reflector service
                echo "# Reflector config for the systemd service"
                echo "--save /etc/pacman.d/mirrorlist"
                [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && echo "--country ${ARCH_OS_REFLECTOR_COUNTRY}"
                echo "--completion-percent 95"
                echo "--protocol https"
                echo "--latest 5"
                echo "--sort rate"
            } >/mnt/etc/xdg/reflector/reflector.conf
            # Enable services
            arch-chroot /mnt systemctl enable reflector.service    # Rank mirrors after boot (reflector)
            arch-chroot /mnt systemctl enable paccache.timer       # Discard cached/unused packages weekly (pacman-contrib)
            arch-chroot /mnt systemctl enable pkgfile-update.timer # Pkgfile update timer (pkgfile)
            process_return 0                                       # Return
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_install_app() {
    local process_name="Install Arch OS App"
    if [ "$ARCH_OS_APP_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0                       # If debug mode then return
            chroot_pacman_install git base-devel kitty gum libnotify ttf-firacode-nerd # Install dependencies
            if [ -z "$ARCH_OS_AUR_HELPER" ] || [ "$ARCH_OS_AUR_HELPER" = "none" ]; then
                chroot_aur_install paru-bin # Install AUR Helper if not enabled
            fi
            chroot_aur_install arch-os-app # Install app
            process_return 0               # Return
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

exec_install_shell_enhancement() {
    local process_name="Install Shell Enhancement"
    if [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0                                   # If debug mode then return
            chroot_pacman_install fish starship eza bat neofetch mc btop nano man-db               # Install packages
            mkdir -p "/mnt/root/.config/fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish"         # Create fish config dirs
            mkdir -p "/mnt/root/.config/neofetch" "/mnt/home/${ARCH_OS_USERNAME}/.config/neofetch" # Create neofetch config dirs
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
            # Set nano environment
            {
                echo 'EDITOR=nano'
                echo 'VISUAL=nano'
            } >/mnt/etc/environment
            # Set Nano colors
            sed -i "s/^# set linenumbers/set linenumbers/" /mnt/etc/nanorc
            sed -i "s/^# set minibar/set minibar/" /mnt/etc/nanorc
            sed -i 's;^# include "/usr/share/nano/\*\.nanorc";include "/usr/share/nano/*.nanorc"\ninclude "/usr/share/nano/extra/*.nanorc";g' /mnt/etc/nanorc
            # Set correct permissions
            arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"
            # Set Shell for root & user
            arch-chroot /mnt chsh -s /usr/bin/fish
            arch-chroot /mnt chsh -s /usr/bin/fish "$ARCH_OS_USERNAME"
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_run $! "$process_name"
    fi
}

# ----------------------------------------------------------------------------------------------------

# shellcheck disable=SC2016
exec_cleanup_installation() {
    local process_name="Cleanup Installation"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0                                                  # If debug mode then return
        cp "$SCRIPT_CONF" "/mnt/home/${ARCH_OS_USERNAME}/installer.conf"                                      # Copy installer files to users home dir
        arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"         # Set home permission
        arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Rns --noconfirm $(pacman -Qtdq) || true' # Remove orphans and force return true
        process_return 0                                                                                      # Return
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////////////  START MAIN  ///////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"
