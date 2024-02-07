#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2317

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////// ARCH OS INSTALLER /////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# SOURCE:   https://github.com/murkl/arch-os
# AUTOR:    murkl
# ORIGIN:   Germany
# LICENCE:  GPL 2.0

# VERSION
VERSION='1.3.0'

# CONFIGURATION
set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -e          # Terminate if any command exits with a non-zero
set -E          # ERR trap inherited by shell functions (errtrace)

# ENVIRONMENT
SCRIPT_CONF="./installer.conf"
SCRIPT_LOG="./installer.log"

# PROCESS
PROCESS_NAME=""
PROCESS_PID=""

# ERROR
ERROR_MSG=""

# COLORS
COLOR_RESET='\e[0m'
COLOR_BOLD='\e[1m'
COLOR_RED='\e[31m'
COLOR_GREEN='\e[32m'
COLOR_PURPLE='\e[35m'
COLOR_YELLOW='\e[33m'

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Set traps
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR
    trap 'trap_exit' EXIT

    # Check gum binary or download
    if [ ! -x ./gum ] && ! command -v /usr/bin/gum &>/dev/null; then
        # Loading
        wait && clear && echo "Loading Arch OS Installer..."

        # Clean cache dir
        local gum_cache="${HOME}/.cache/arch-os-gum"
        rm -rf "$gum_cache"
        mkdir -p "$gum_cache"

        # Download gum
        local gum_url="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_x86_64.tar.gz"
        curl -Ls "$gum_url" >"${gum_cache}/gum.tar.gz"
        tar -xf "${gum_cache}/gum.tar.gz" --directory "$gum_cache"
        mv "${gum_cache}/gum" ./gum
        chmod +x ./gum
        rm -rf "$gum_cache"
    fi

    # Print header
    clear && echo -e "${COLOR_PURPLE}
  █████  ██████   ██████ ██   ██      ██████  ███████ 
 ██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
 ███████ ██████  ██      ███████     ██    ██ ███████ 
 ██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
 ██   ██ ██   ██  ██████ ██   ██      ██████  ███████
 ${COLOR_RESET}"

    # Move installer.log if exists
    [ -f "$SCRIPT_LOG" ] && mv "$SCRIPT_LOG" "${SCRIPT_LOG}.bak" && echo "Moved installer.log to installer.log.bak" >>"$SCRIPT_LOG"

    # Print welcome
    print_info "Welcome to the Arch OS Installer (${VERSION})"

    # Check if properties file exists
    [ ! -f "$SCRIPT_CONF" ] && print_error "Properties file '${SCRIPT_CONF}' not found" && exit 1

    # Prepare properties
    properties_default  # Set default properties
    properties_source   # Load properties file and auto export variables
    properties_generate # Generate & source properties
    properties_source   # Source generated properties

    # Selectors
    until select_username; do :; done
    until select_password; do :; done
    #select_timezone
    #select_language
    #select_keyboard
    #select_disk
    #select_encryption
    #select_bootsplash
    #select_variant (+ driver as seperated print_info)

    # Show properties?
    if gum confirm "Show all Properties?"; then
        gum pager <"$SCRIPT_CONF"
        if gum confirm "Edit Properties?"; then
            if gum write --char-limit=5000 --height=20 --width=100 --header="Exit with CTRL + C and save with CTRL + D or ESC" --value="$(cat $SCRIPT_CONF)" >installer.conf.new; then
                mv installer.conf.new installer.conf
                properties_source
            else
                rm -f installer.conf.new
            fi
        fi
    fi

    # Check properties
    properties_check && print_info "Properties successfully initialized"

    # Start Arch OS Installation?
    if ! gum confirm "Start Arch OS Installation?"; then
        print_warn "Exit..."
        exit 0
    fi

    # Wait 5 seconds ...
    sleep 5 &
    PROCESS_PID="$!" && gum_spinner "$PROCESS_PID" "Arch OS Installation starts in 5 seconds. Press CTRL + C to cancel"

    # Start installation
    print_info "Start Arch OS Installation..."

    # Messure execution time of installation
    SECONDS=0

    # Executors
    exec_init
    exec_init
    exec_init
    #exec_disk
    #exec_bootloader
    #exec_bootsplash
    #exec_aur_helper
    #exec_multilib
    #exec_desktop
    #exec_shell_enhancement
    #exec_graphics_driver
    #exec_vm_support
    #exec_cleanup
    # ...

    # Calc installation duration
    duration=$SECONDS # This is set before install starts
    duration_min="$((duration / 60))"
    duration_sec="$((duration % 60))"

    # Print finish
    print_info "Arch OS successfully installed after ${duration_min} minutes and ${duration_sec} seconds"

    # Reboot
    if gum confirm "Reboot to Arch OS now?"; then
        print_warn "Rebooting..."
        #reboot
    fi

    exit 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROPERTIES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

properties_source() {
    set -a # Enable auto export of variables
    source "$SCRIPT_CONF"
    set +a # Disable auto export of variables
}

# ----------------------------------------------------------------------------------------------------

properties_default() {
    [ -z "$ARCH_OS_HOSTNAME" ] && ARCH_OS_HOSTNAME="arch-os"
    [ -z "$ARCH_OS_KERNEL" ] && ARCH_OS_KERNEL="linux-zen"
    [ -z "$ARCH_OS_VM_SUPPORT_ENABLED" ] && ARCH_OS_VM_SUPPORT_ENABLED="true"
    [ -z "$ARCH_OS_SHELL_ENHANCED_ENABLED" ] && ARCH_OS_SHELL_ENHANCED_ENABLED="true"
    [ -z "$ARCH_OS_AUR_HELPER" ] && ARCH_OS_AUR_HELPER="paru"
    [ -z "$ARCH_OS_MULTILIB_ENABLED" ] && ARCH_OS_MULTILIB_ENABLED="true"
    [ -z "$ARCH_OS_ECN_ENABLED" ] && ARCH_OS_ECN_ENABLED="true"
    [ -z "$ARCH_OS_X11_KEYBOARD_MODEL" ] && ARCH_OS_X11_KEYBOARD_MODEL="pc105"
    [ -z "$ARCH_OS_GRAPHICS_DRIVER" ] && ARCH_OS_GRAPHICS_DRIVER="mesa"
    [ -z "$ARCH_OS_X11_KEYBOARD_LAYOUT" ] && ARCH_OS_X11_KEYBOARD_LAYOUT="us"
    [ -z "$ARCH_OS_MICROCODE" ] && grep -E "GenuineIntel" &>/dev/null <<<"$(lscpu) " && ARCH_OS_MICROCODE="intel-ucode"
    [ -z "$ARCH_OS_MICROCODE" ] && grep -E "AuthenticAMD" &>/dev/null <<<"$(lscpu)" && ARCH_OS_MICROCODE="amd-ucode"
    return 0
}

# ----------------------------------------------------------------------------------------------------

properties_check() {
    [ -z "${ARCH_OS_USERNAME}" ] && print_error "Property: 'ARCH_OS_USERNAME' is missing" && exit 1
    [ -z "${ARCH_OS_PASSWORD}" ] && print_error "Property: 'ARCH_OS_PASSWORD' is missing" && exit 1
    [ -z "${ARCH_OS_HOSTNAME}" ] && print_error "Property: 'ARCH_OS_HOSTNAME' is missing" && exit 1
    [ -z "${ARCH_OS_TIMEZONE}" ] && print_error "Property: 'ARCH_OS_TIMEZONE' is missing" && exit 1
    [ -z "${ARCH_OS_LOCALE_LANG}" ] && print_error "Property: 'ARCH_OS_LOCALE_LANG' is missing" && exit 1
    [ -z "${ARCH_OS_LOCALE_GEN_LIST[*]}" ] && print_error "Property: 'ARCH_OS_LOCALE_GEN_LIST' is missing" && exit 1
    [ -z "${ARCH_OS_VCONSOLE_KEYMAP}" ] && print_error "Property: 'ARCH_OS_VCONSOLE_KEYMAP' is missing" && exit 1
    [ -z "${ARCH_OS_DISK}" ] && print_error "Property: 'ARCH_OS_DISK' is missing" && exit 1
    [ -z "${ARCH_OS_BOOT_PARTITION}" ] && print_error "Property: 'ARCH_OS_BOOT_PARTITION' is missing" && exit 1
    [ -z "${ARCH_OS_ROOT_PARTITION}" ] && print_error "Property: 'ARCH_OS_ROOT_PARTITION' is missing" && exit 1
    [ -z "${ARCH_OS_ENCRYPTION_ENABLED}" ] && print_error "Property: 'ARCH_OS_ENCRYPTION_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_BOOTSPLASH_ENABLED}" ] && print_error "Property: 'ARCH_OS_BOOTSPLASH_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_KERNEL}" ] && print_error "Property: 'ARCH_OS_KERNEL' is missing" && exit 1
    [ -z "${ARCH_OS_MICROCODE}" ] && print_error "Property: 'ARCH_OS_MICROCODE' is missing" && exit 1
    [ -z "${ARCH_OS_VARIANT}" ] && print_error "Property: 'ARCH_OS_VARIANT' is missing" && exit 1
    [ -z "${ARCH_OS_SHELL_ENHANCED_ENABLED}" ] && print_error "Property: 'ARCH_OS_SHELL_ENHANCED_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_AUR_HELPER}" ] && print_error "Property: 'ARCH_OS_AUR_HELPER' is missing" && exit 1
    [ -z "${ARCH_OS_MULTILIB_ENABLED}" ] && print_error "Property: 'ARCH_OS_MULTILIB_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_GRAPHICS_DRIVER}" ] && print_error "Property: 'ARCH_OS_GRAPHICS_DRIVER' is missing" && exit 1
    [ -z "${ARCH_OS_X11_KEYBOARD_LAYOUT}" ] && print_error "Property: 'ARCH_OS_X11_KEYBOARD_LAYOUT' is missing" && exit 1
    [ -z "${ARCH_OS_X11_KEYBOARD_MODEL}" ] && print_error "Property: 'ARCH_OS_X11_KEYBOARD_MODEL' is missing" && exit 1
    [ -z "${ARCH_OS_VM_SUPPORT_ENABLED}" ] && print_error "Property: 'ARCH_OS_VM_SUPPORT_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_ECN_ENABLED}" ] && print_error "Property: 'ARCH_OS_ECN_ENABLED' is missing" && exit 1
    return 0
}

# ----------------------------------------------------------------------------------------------------

properties_generate() {
    {
        echo "# Arch OS ${VERSION} ($(date --utc '+%Y-%m-%d %H:%M:%S') UTC)"
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
    } >"$SCRIPT_CONF"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_username() {
    if [ -z "${ARCH_OS_USERNAME}" ]; then
        ! ARCH_OS_USERNAME=$(gum input --prompt=" • " --placeholder="Please enter Username") && exit 1
        [ -z "${ARCH_OS_USERNAME}" ] && return 1
    fi
    properties_generate && print_info "Username is set to ${ARCH_OS_USERNAME}"
}

# ----------------------------------------------------------------------------------------------------

select_password() {
    if [ -z "${ARCH_OS_PASSWORD}" ]; then
        ! ARCH_OS_PASSWORD=$(gum input --prompt=" • " --password --placeholder="Please enter Password") && exit 1
        [ -z "${ARCH_OS_PASSWORD}" ] && return 1
    fi
    properties_generate && print_info "Password is set to *********"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# EXECUTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init() {
    # ----------------------------------------------------------------------------------------------------
    PROCESS_NAME="Prepare Installation"
    # ----------------------------------------------------------------------------------------------------
    if [ -n "${HOME}" ]; then
        log_process "$PROCESS_NAME" # Print process to log
        # Start subprocess async and print stdin & sterr to logfile
        {
            sleep 3
        } &>>"$SCRIPT_LOG" &
        # Save pid of subprocess, open spinner and print process to stdout
        PROCESS_PID="$!" && gum_spinner "$PROCESS_PID" "$PROCESS_NAME" && print_process "$PROCESS_NAME"
    fi
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOG & PRINT
# ////////////////////////////////////////////////////////////////////////////////////////////////////

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >>"$SCRIPT_LOG"
}

# ----------------------------------------------------------------------------------------------------

log_process() {
    log "EXEC: ${*}"
}

# ----------------------------------------------------------------------------------------------------

print_info() {
    log "INFO: ${*}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN} • ${*}${COLOR_RESET}"
}

# ----------------------------------------------------------------------------------------------------

print_warn() {
    log "WARN: ${*}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW} • ${*}${COLOR_RESET}"
}

# ----------------------------------------------------------------------------------------------------

print_error() {
    log "ERROR: ${*}"
    echo -e "${COLOR_BOLD}${COLOR_RED} • ${*} ${COLOR_RESET}"
}

# ----------------------------------------------------------------------------------------------------

print_input() {
    log "USER: ${*}"
    echo -ne "${COLOR_BOLD}${COLOR_YELLOW} + ${1} ${COLOR_RESET}"
}

# ----------------------------------------------------------------------------------------------------

print_process() {
    echo -e "${COLOR_BOLD}${COLOR_GREEN} + ${*} ${COLOR_RESET}"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM
# ////////////////////////////////////////////////////////////////////////////////////////////////////

gum() {
    if [ -x ./gum ]; then ./gum "$@"; else /usr/bin/gum "$@"; fi # Force open ./gum if exists
}

# ----------------------------------------------------------------------------------------------------

gum_spinner() {
    gum spin --title.foreground="212" --spinner.foreground="212" --spinner dot --title "${2}..." -- bash -c "while kill -0 $1 2> /dev/null; do sleep 1; done"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# TRAPS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

trap_error() {
    ERROR_MSG="Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})"
}

# ----------------------------------------------------------------------------------------------------

trap_exit() {
    local result_code="$?"

    # Check if failed
    if [ "$result_code" -gt "0" ]; then

        # Check if pid is already running (only on SIGINT with ctrl + c)
        if kill -0 "$PROCESS_PID" 2>/dev/null; then
            kill "$PROCESS_PID"
            print_warn "Process with PID ${PROCESS_PID} was killed"
        else
            # When not canceled check if error is set and print
            [ -n "$ERROR_MSG" ] && print_error "$ERROR_MSG"
        fi

        # Default prints if failed
        print_error "Arch OS Installation failed"
        print_warn "For more information see ./installer.log"
    fi

    # Exit installer.sh
    exit "$result_code"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////////////  START MAIN  ///////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"
