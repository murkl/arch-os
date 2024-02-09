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

# ENVIRONMENT
SCRIPT_CONF="./installer.conf"
SCRIPT_LOG="./installer.log"

# PROCESS
PROCESS_LOCK="./process.lock"
PROCESS_LOG="./process.log"
PROCESS_PID=""
PROCESS_NAME=""

# GUM
GUM_URL="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_x86_64.tar.gz"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Configuration
    set -o pipefail # A pipeline error results in the error status of the entire pipeline
    set -e          # Terminate if any command exits with a non-zero
    set -E          # ERR trap inherited by shell functions (errtrace)

    # Init
    gum_init              # Check gum binary or download
    rm -f "$SCRIPT_LOG"   # Clear logfile
    rm -f "$PROCESS_LOCK" # Clear process lock

    # Traps (error & exit)
    trap 'trap_exit' EXIT
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

    while (true); do # Loop properties step to update screen if user edit properties

        # Prepare properties
        properties_default  # Set default properties
        properties_source   # Load properties file (if exists) and auto export variables
        properties_generate # Generate properties file (needed on first start of installer)
        properties_source   # Source generated properties (needed on first start of installer)

        # Print Welcome
        print_header && print_title "Welcome to Arch OS Installation"

        # Selectors
        until select_username; do :; done
        until select_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_disk; do :; done
        until select_encryption; do :; done
        until select_bootsplash; do :; done
        until select_variant; do :; done

        # Edit properties?
        if gum confirm "Edit Properties?"; then
            print_header && print_title "Edit Properties"
            local gum_header="Exit with CTRL + C and save with CTRL + D or ESC"
            gum write --show-cursor-line --prompt=" • " --char-limit=0 --height=25 --width=100 --header=" ${gum_header}" --value="$(cat "$SCRIPT_CONF")" >"${SCRIPT_CONF}.new" && mv "${SCRIPT_CONF}.new" "${SCRIPT_CONF}"
            rm -f "${SCRIPT_CONF}.new" # Remove tmp properties
            gum confirm "Change Password?" && until select_password --force; do :; done
            continue # Restart properties step
        fi

        # Check properties
        properties_check && print_info "Properties successfully initialized"
        break # Exit properties step

    done

    # Start installation in 5 seconds?
    gum confirm "Start Arch OS Installation?" || trap_gum_exit
    local spin_title="Arch OS Installation starts in 5 seconds. Press CTRL + C to cancel"
    gum spin --title.foreground="212" --spinner.foreground="212" --spinner line --title=" $spin_title" -- sleep 0.5 || trap_gum_exit # CTRL + C pressed
    print_info "Start Arch OS Installation..."

    SECONDS=0 # Messure execution time of installation

    # Executors
    exec_init
    exec_disk
    exec_bootloader
    exec_bootsplash
    exec_aur_helper
    exec_multilib
    exec_desktop
    exec_shell_enhancement
    exec_graphics_driver
    exec_vm_support
    exec_cleanup

    # Calc installation duration
    duration=$SECONDS # This is set before install starts
    duration_min="$((duration / 60))"
    duration_sec="$((duration % 60))"

    # Finish & reboot
    print_info "Successfully installed after ${duration_min} minutes and ${duration_sec} seconds"
    gum confirm "Reboot to Arch OS now?" && print_warn "Rebooting..." && echo "reboot"
    exit 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# TRAPS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

trap_error() {
    # If process calls this trap, write error to file to use in exit trap
    echo "Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})" >installer.err
}

trap_exit() {
    local result_code="$?"
    # Check if failed
    if [ "$result_code" -gt "0" ]; then
        [ "$result_code" = "130" ] && print_warn "Exit..." && exit 1             # When ctrl + c pressed exit without other stuff
        [ -f installer.err ] && local error && error="$(<installer.err)"         # Read error msg from file (written in error trap)
        [ -n "$error" ] && print_fail "$error"                                   # Print error message (if exists)
        [ -z "$error" ] && print_fail "Arch OS Installation failed"              # Otherwise pint default error message
        gum confirm "Show Logs?" && gum pager --show-line-numbers <"$SCRIPT_LOG" # Ask for show logs?
    fi
    exit "$result_code" # Exit installer.sh
}

trap_gum_exit() {
    exit 130
}

trap_gum_exit_confirm() {
    gum confirm "Exit Installation?" && trap_gum_exit
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    [ -f "$PROCESS_LOCK" ] && print_fail "${PROCESS_LOCK} already exists" && exit 1
    PROCESS_NAME="$1"                    # Set process name
    echo 1 >"$PROCESS_LOCK"              # Init lock with 1
    log_proc "Start: ${PROCESS_NAME}..." # Log starting
}

process_run() {
    PROCESS_PID="$1"            # Set process pid
    local user_canceled="false" # Will set to true if user press ctrl + c

    # Show gum spinner until pid is not exists anymore and set user_canceled to true on failure
    gum spin --title.foreground="212" --spinner.foreground="212" --spinner line --title " ${PROCESS_NAME}..." -- bash -c "while ps -p $PROCESS_PID > /dev/null; do sleep 1; done" || user_canceled="true"
    cat "$PROCESS_LOG" >>"$SCRIPT_LOG" # Write process log to logfile

    # When user press ctrl + c while process is running
    if [ "$user_canceled" = "true" ]; then
        ps -p "$PROCESS_PID" >/dev/null && kill "$PROCESS_PID"                           # Kill process if running
        print_fail "Process with PID ${PROCESS_PID} was killed by user" && trap_gum_exit # Exit with 130
    fi

    # Handle error while executing process
    [ ! -f "$PROCESS_LOCK" ] && print_fail "${PROCESS_LOCK} not found (do not init process?)" && exit 1
    [ "$(<"$PROCESS_LOCK")" != "0" ] && print_fail "${PROCESS_NAME} failed" && exit 1 # If process failed (result code 0 was not write in the end)

    # Finish
    rm -f "$PROCESS_LOCK"                             # Remove process lock file
    log_proc "Sucessful: ${PROCESS_NAME}"             # Log process sucess
    print_proc "${PROCESS_NAME} sucessfully deployed" # Print process success
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOG & PRINT
# ////////////////////////////////////////////////////////////////////////////////////////////////////

print_header() {
    local logo='
  █████  ██████   ██████ ██   ██      ██████  ███████ 
 ██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
 ███████ ██████  ██      ███████     ██    ██ ███████ 
 ██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
 ██   ██ ██   ██  ██████ ██   ██      ██████  ███████
 
 '
    local title_gum && title_gum=$(gum style --foreground 255 "Arch OS Installer ${VERSION}")
    clear && gum style --border normal --align center --margin "1 1" --padding "0 2" --foreground 212 --border-foreground 255 "${logo} ${title_gum}"
}

# Log
log_write() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >>"$SCRIPT_LOG"; }
log_info() { log_write "INFO | ${*}"; }
log_warn() { log_write "WARN | ${*}"; }
log_fail() { log_write "FAIL | ${*}"; }
log_user() { log_write "USER | ${*}"; }
log_proc() { log_write "PROC | ${*}"; }

# Colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
print_blue() { gum style --foreground 39 "${*}"; }    # To new stdout (3)
print_purple() { gum style --foreground 212 "${*}"; } # To new stdout (3)
print_green() { gum style --foreground 42 "${*}"; }   # To new stdout (3)
print_yellow() { gum style --foreground 220 "${*}"; } # To new stdout (3)
print_red() { gum style --foreground 197 "${*}"; }    # To new stdout (3)

# Print
print_title() { gum style --foreground 212 " ${*}"; }
print_info() { log_info "$*" && print_green " • ${*}"; }
print_warn() { log_warn "$*" && print_yellow " • ${*}"; }
print_fail() { log_fail "$*" && print_red " • ${*}"; }
print_user() { log_user "$*" && print_green " + ${*}"; }
print_proc() { print_purple " + ${*} "; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM
# ////////////////////////////////////////////////////////////////////////////////////////////////////

gum_init() {
    if [ ! -x ./gum ] && ! command -v /usr/bin/gum &>/dev/null; then
        clear && echo "Loading Arch OS Installer..." # Loading
        local gum_cache="${HOME}/.cache/arch-os-gum" # Cache dir
        rm -rf "$gum_cache"                          # Clean cache dir
        if ! mkdir -p "$gum_cache"; then echo "Error creating ${gum_cache}" && exit 1; fi
        if ! curl -Lsf "$GUM_URL" >"${gum_cache}/gum.tar.gz"; then echo "Error downloading ${GUM_URL}" && exit 1; fi
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
# PROPERTIES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

properties_source() {
    if [ -f "$SCRIPT_CONF" ]; then
        set -a # Enable auto export of variables
        source "$SCRIPT_CONF"
        set +a # Disable auto export of variables
    fi
}

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

properties_check() {
    [ -z "${ARCH_OS_USERNAME}" ] && print_fail "Property: 'ARCH_OS_USERNAME' is missing" && exit 1
    [ -z "${ARCH_OS_PASSWORD}" ] && print_fail "Property: 'ARCH_OS_PASSWORD' is missing" && exit 1
    [ -z "${ARCH_OS_HOSTNAME}" ] && print_fail "Property: 'ARCH_OS_HOSTNAME' is missing" && exit 1
    [ -z "${ARCH_OS_TIMEZONE}" ] && print_fail "Property: 'ARCH_OS_TIMEZONE' is missing" && exit 1
    [ -z "${ARCH_OS_LOCALE_LANG}" ] && print_fail "Property: 'ARCH_OS_LOCALE_LANG' is missing" && exit 1
    [ -z "${ARCH_OS_LOCALE_GEN_LIST[*]}" ] && print_fail "Property: 'ARCH_OS_LOCALE_GEN_LIST' is missing" && exit 1
    [ -z "${ARCH_OS_VCONSOLE_KEYMAP}" ] && print_fail "Property: 'ARCH_OS_VCONSOLE_KEYMAP' is missing" && exit 1
    [ -z "${ARCH_OS_DISK}" ] && print_fail "Property: 'ARCH_OS_DISK' is missing" && exit 1
    [ -z "${ARCH_OS_BOOT_PARTITION}" ] && print_fail "Property: 'ARCH_OS_BOOT_PARTITION' is missing" && exit 1
    [ -z "${ARCH_OS_ROOT_PARTITION}" ] && print_fail "Property: 'ARCH_OS_ROOT_PARTITION' is missing" && exit 1
    [ -z "${ARCH_OS_ENCRYPTION_ENABLED}" ] && print_fail "Property: 'ARCH_OS_ENCRYPTION_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_BOOTSPLASH_ENABLED}" ] && print_fail "Property: 'ARCH_OS_BOOTSPLASH_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_KERNEL}" ] && print_fail "Property: 'ARCH_OS_KERNEL' is missing" && exit 1
    [ -z "${ARCH_OS_MICROCODE}" ] && print_fail "Property: 'ARCH_OS_MICROCODE' is missing" && exit 1
    [ -z "${ARCH_OS_VARIANT}" ] && print_fail "Property: 'ARCH_OS_VARIANT' is missing" && exit 1
    [ -z "${ARCH_OS_SHELL_ENHANCED_ENABLED}" ] && print_fail "Property: 'ARCH_OS_SHELL_ENHANCED_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_AUR_HELPER}" ] && print_fail "Property: 'ARCH_OS_AUR_HELPER' is missing" && exit 1
    [ -z "${ARCH_OS_MULTILIB_ENABLED}" ] && print_fail "Property: 'ARCH_OS_MULTILIB_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_GRAPHICS_DRIVER}" ] && print_fail "Property: 'ARCH_OS_GRAPHICS_DRIVER' is missing" && exit 1
    [ -z "${ARCH_OS_X11_KEYBOARD_LAYOUT}" ] && print_fail "Property: 'ARCH_OS_X11_KEYBOARD_LAYOUT' is missing" && exit 1
    [ -z "${ARCH_OS_X11_KEYBOARD_MODEL}" ] && print_fail "Property: 'ARCH_OS_X11_KEYBOARD_MODEL' is missing" && exit 1
    [ -z "${ARCH_OS_VM_SUPPORT_ENABLED}" ] && print_fail "Property: 'ARCH_OS_VM_SUPPORT_ENABLED' is missing" && exit 1
    [ -z "${ARCH_OS_ECN_ENABLED}" ] && print_fail "Property: 'ARCH_OS_ECN_ENABLED' is missing" && exit 1
    return 0
}

properties_generate() {
    {
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
    if [ -z "$ARCH_OS_USERNAME" ]; then
        ARCH_OS_USERNAME=$(gum input --prompt=" + " --prompt.foreground="212" --placeholder="Please enter Username") || trap_gum_exit_confirm
        [ -z "${ARCH_OS_USERNAME}" ] && return 1 # Check if new value is null
        properties_generate                      # Generate properties file
    fi
    print_user "Username is set to ${ARCH_OS_USERNAME}"
}

# ----------------------------------------------------------------------------------------------------

select_password() {
    if [ "$1" = "--force" ] || [ -z "$ARCH_OS_PASSWORD" ]; then
        ARCH_OS_PASSWORD=$(gum input --password --prompt=" + " --prompt.foreground="212" --placeholder="Please enter Password") || trap_gum_exit_confirm
        [ -z "${ARCH_OS_PASSWORD}" ] && return 1 # Check if new value is null
        properties_generate                      # Generate properties file
    fi
    print_user "Password is set to *******"
}

# ----------------------------------------------------------------------------------------------------

select_timezone() {
    true
}

# ----------------------------------------------------------------------------------------------------

select_language() {
    true
}

# ----------------------------------------------------------------------------------------------------

select_keyboard() {
    true
}

# ----------------------------------------------------------------------------------------------------

select_disk() {
    true
}

# ----------------------------------------------------------------------------------------------------

select_encryption() {
    true
}

# ----------------------------------------------------------------------------------------------------

select_bootsplash() {
    true
}

# ----------------------------------------------------------------------------------------------------

select_variant() {
    true # Driver as seperated print_info
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# EXECUTORS (SUB PROCESSES)
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init() {
    process_init "Initialize Installation"
    (
        echo "stdou"
        echo "stderr" >&2
        sleep 1.2
        #false
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_disk() {
    process_init "Prepare Disk"
    (
        sleep 2
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_bootloader() {
    process_init "Install Bootloader"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_bootsplash() {
    process_init "Install Bootsplash"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_aur_helper() {
    process_init "Install AUR Helper"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_multilib() {
    process_init "Enable Multilib"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_desktop() {
    process_init "Install Desktop"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_shell_enhancement() {
    process_init "Install Shell Enhancement"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_graphics_driver() {
    process_init "Install Graphics Driver"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_vm_support() {
    process_init "Install VM Support"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_cleanup() {
    process_init "Cleanup Installation"
    (
        sleep 1
    ) &>"$PROCESS_LOG" && echo 0 >"$PROCESS_LOCK" &
    process_run $!
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////////////  START MAIN  ///////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"
