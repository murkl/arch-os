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
PROCESS_PID=""
PROCESS_NAME=""

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Configuration
    wait && clear        # Clear screen
    set -o pipefail      # A pipeline error results in the error status of the entire pipeline
    set -e               # Terminate if any command exits with a non-zero
    set -E               # ERR trap inherited by shell functions (errtrace)
    exec 3>&1 4>&2       # Saves file descriptors (new stdout: 3 new stderr: 4)
    exec 1>/dev/null     # Write stdout to /dev/null
    exec 2>"$SCRIPT_LOG" # Write stderr to logfile

    # Set traps (error & exit)
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR
    trap 'trap_exit' EXIT

    # Init gum & print welcome
    gum_init     # Check gum binary or download
    print_header # Print header

    # Prepare properties
    properties_default  # Set default properties
    properties_source   # Load properties file (if exists) and auto export variables
    properties_generate # Generate properties file
    properties_source   # Source generated properties

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
        local gum_header="Exit with CTRL + C and save with CTRL + D or ESC"
        if gum write --show-cursor-line --prompt=" • " --char-limit=0 --height=12 --width=100 --header=" • ${gum_header}" --value="$(cat "$SCRIPT_CONF")" >installer.conf.new; then
            mv installer.conf.new installer.conf
            properties_source
        else
            rm -f installer.conf.new
        fi
    fi

    # Check properties
    properties_check && print_info "Properties successfully initialized"

    # Start installation in 5 seconds?
    ! gum confirm "Start Arch OS Installation?" && exit 130
    local spin_title="Arch OS Installation starts in 5 seconds. Press CTRL + C to cancel"
    ! gum spin --title.foreground="212" --spinner.foreground="212" --spinner line --title=" $spin_title" -- sleep 5 && exit 130
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
    if kill -0 "$PROCESS_PID" 2>/dev/null; then # Check if pid is already running (only on SIGINT with ctrl + c)
        kill "$PROCESS_PID" && log_warn "Process with PID ${PROCESS_PID} was killed"
    else # When user not canceled print error
        print_fail "Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})"
    fi
}

trap_exit() {
    local result_code="$?"
    # When ctrl + c pressed exit without other stuff
    [ "$result_code" = "130" ] && print_warn "Exit..." && exit 1
    if [ "$result_code" -gt "0" ]; then # Check if failed
        print_fail "Arch OS Installation failed"
        exec 1>&3 2>&4 # Reset redirect (needed for access to logfile)
        gum confirm "Show Logs?" && gum pager --show-line-numbers "$@" <"$SCRIPT_LOG"
    fi
    rm -f "$PROCESS_LOCK" # Remove process lock
    exit "$result_code"   # Exit installer.sh
}

trap_gum() {
    gum confirm "Exit Installation?" && exit 130
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
    #| tee /dev/fd/3 >&2 # Print to new stdout (3) and logfile
    local welcome_gum && welcome_gum=$(gum style --foreground 212 "Welcome to Arch OS Installer ${VERSION}")
    gum style --border normal --align center --margin "0 1" --padding "0 2" --foreground 255 --border-foreground 212 "${logo} ${welcome_gum}" >&3
    #gum style --border normal --align center --margin "0 1" --padding "0 2" --foreground 255 --border-foreground 212 "${logo} ${welcome_txt}" >&3
    #gum join "$logo_gum" "$welcome_gum" >&3
    #echo "$logo_gum" >&3
}

# Log
log_write() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >&2; } # To stderr (logfile)
log_info() { log_write "INFO | ${*}"; }
log_warn() { log_write "WARN | ${*}"; }
log_fail() { log_write "FAIL | ${*}"; }
log_user() { log_write "USER | ${*}"; }
log_proc() { log_write "PROC | ${*}"; }

# Colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
print_blue() { gum style --foreground 39 "${*}" >&3; }    # To new stdout (3)
print_purple() { gum style --foreground 212 "${*}" >&3; } # To new stdout (3)
print_green() { gum style --foreground 42 "${*}" >&3; }   # To new stdout (3)
print_yellow() { gum style --foreground 220 "${*}" >&3; } # To new stdout (3)
print_red() { gum style --foreground 197 "${*}" >&3; }    # To new stdout (3)

# Print
print_info() { log_info "$*" && print_green " • ${*}"; }
print_warn() { log_warn "$*" && print_yellow " • ${*}"; }
print_fail() { log_fail "$*" && print_red " • ${*}"; }
print_user() { log_user "$*" && print_blue " + ${*}"; }
print_proc() { print_purple " + ${*} "; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM
# ////////////////////////////////////////////////////////////////////////////////////////////////////

gum_init() {
    if [ ! -x ./gum ] && ! command -v /usr/bin/gum &>/dev/null; then
        # Loading
        echo "Loading Arch OS Installer..."
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
}

gum() {
    local gum="./gum" && [ ! -x "$gum" ] && gum="/usr/bin/gum" # Force open ./gum if exists
    case $2 in                                                 # Redirect to correct descriptors
    pager) $gum "$@" 1>&3 2>&4 ;;                              # Print stdout & stderr to new descriptors
    #style) $gum "$@" >&3 ;;                                   # Print to new stdout (3)
    *) $gum "$@" 2>&4 ;; # Print stderr (gum default) to new stderr
    esac
}

gum_input() {
    local desc="$1" && shift
    local key="$1" && shift
    local value && value="$(eval "echo \"\$$key\"")" # Set current value
    if [ -z "$value" ]; then
        value=$(gum input --prompt=" • " --placeholder="Please enter ${desc}" "$@") || trap_gum
        [ -z "${value}" ] && return 1 # Check if new value is null
        eval "$key=\"$value\""        # Set new value
        properties_generate           # Generate properties file
    fi
    print_user "${desc} is set to ${value}"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    [ -f "$PROCESS_LOCK" ] && print_fail "${PROCESS_LOCK} already exists" && exit 1
    PROCESS_NAME="$1"
    echo 1 >"$PROCESS_LOCK" # Initialize with 1
    log_proc "Start process '${PROCESS_NAME}'..."
    return 0
}

process_run() {
    PROCESS_PID="$1"
    # Show gum spinner until pid is not exists anymore
    gum spin --title.foreground="212" --spinner.foreground="212" --spinner line --title " ${PROCESS_NAME}..." -- tail -f /dev/null --pid "$PROCESS_PID" || (
        print_fail "Process was canceled by user" && exit 1 # When user press ctrl + c while process is running
    )
    wait && [ ! -f "$PROCESS_LOCK" ] && print_fail "${PROCESS_LOCK} not found (do not init process?)" && exit 1
    local gum_result && gum_result="$(<$PROCESS_LOCK)" # Read result from process lock
    rm -f "$PROCESS_LOCK"                              # Remove process lock file
    [ "$gum_result" != "0" ] && exit 1                 # If process result code is err (higher 0) exit script
    print_proc "$PROCESS_NAME"                         # Print process
    return 0
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
    gum_input "Username" "ARCH_OS_USERNAME"
}

# ----------------------------------------------------------------------------------------------------

select_password() {
    gum_input "Password" "ARCH_OS_PASSWORD" --password
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
# EXECUTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init() {
    process_init "Initialize Installation"
    {
        #false || exit 1
        sleep 3
        echo 0 >"$PROCESS_LOCK"
    } &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_disk() {
    process_init "Prepare Disk"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_bootloader() {
    process_init "Install Bootloader"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_bootsplash() {
    process_init "Install Bootsplash"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_aur_helper() {
    process_init "Install AUR Helper"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_multilib() {
    process_init "Enable Multilib"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_desktop() {
    process_init "Install Desktop"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_shell_enhancement() {
    process_init "Install Shell Enhancement"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_graphics_driver() {
    process_init "Install Graphics Driver"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_vm_support() {
    process_init "Install VM Support"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ----------------------------------------------------------------------------------------------------

exec_cleanup() {
    process_init "Cleanup Installation"
    (
        sleep 1
        echo 0 >"$PROCESS_LOCK"
    ) &
    process_run $!
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////////////  START MAIN  ///////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"
