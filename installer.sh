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
VERSION='1.3.0'
GUM_VERSION="0.13.0"

# ENVIRONMENT
SCRIPT_CONF="./installer.conf"
SCRIPT_LOG="./installer.log"

# ERROR
ERROR_MSG="./installer.err"

# PROCESS
PROCESS_LOG="./process.log"
PROCESS_RETURN="./process.rt"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Configuration
    set -o pipefail # A pipeline error results in the error status of the entire pipeline
    set -e          # Terminate if any command exits with a non-zero
    set -E          # ERR trap inherited by shell functions (errtrace)

    # Init
    gum_init                # Check gum binary or download
    rm -f "$SCRIPT_LOG"     # Clear logfile
    rm -f "$PROCESS_RETURN" # Clear process lock

    # Traps (error & exit)
    trap 'trap_exit' EXIT
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

    while (true); do # Loop properties step to update screen if user edit properties

        # Prepare properties
        properties_default  # Set default properties
        properties_source   # Load properties file (if exists) and auto export variables
        properties_generate # Generate properties file (needed on first start of installer)

        # Print Welcome
        print_header && print_title "Welcome to Arch OS Installation!"

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
        if gum_confirm "Edit Properties?"; then
            print_header && print_title "Edit Properties"
            log_info "Edit properties..."
            local gum_header="Exit with CTRL + C and save with CTRL + D or ESC"
            if gum_write --height=25 --width=100 --header=" ${gum_header}" --value="$(cat "$SCRIPT_CONF")" >"${SCRIPT_CONF}.new"; then
                mv "${SCRIPT_CONF}.new" "${SCRIPT_CONF}" && properties_source
            fi
            rm -f "${SCRIPT_CONF}.new" # Remove tmp properties
            gum_confirm "Change Password?" && until select_password --force; do :; done
            continue # Restart properties step
        fi

        # Check properties
        properties_check && print_info "Properties successfully initialized"
        break # Exit properties step

    done

    # Start installation in 5 seconds?
    gum_confirm "Start Arch OS Installation?" || trap_gum_exit
    local spin_title="Arch OS Installation starts in 5 seconds. Press CTRL + C to cancel"
    gum_spin --title=" $spin_title" -- sleep 5 || trap_gum_exit # CTRL + C pressed
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
    gum_confirm "Reboot to Arch OS now?" && print_warn "Rebooting..." && echo "reboot"
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
        local pc_arch
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
    # Check if failed
    if [ "$result_code" -gt "0" ]; then
        [ "$result_code" = "130" ] && print_warn "Exit..." && exit 1             # When ctrl + c pressed exit without other stuff
        [ -f "$ERROR_MSG" ] && local error && error="$(<"$ERROR_MSG")"           # Read error msg from file (written in error trap)
        [ -n "$error" ] && print_fail "$error"                                   # Print error message (if exists)
        [ -z "$error" ] && print_fail "Arch OS Installation failed"              # Otherwise pint default error message
        gum_confirm "Show Logs?" && gum_pager --show-line-numbers <"$SCRIPT_LOG" # Ask for show logs?
    fi
    rm -f "$ERROR_MSG"
    rm -f "$PROCESS_RETURN"
    rm -f "$PROCESS_LOG"
    exit "$result_code" # Exit installer.sh
}

trap_gum_exit() {
    exit 130
}

trap_gum_exit_confirm() {
    gum_confirm "Exit Installation?" && trap_gum_exit
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    [ -f "$PROCESS_RETURN" ] && print_fail "${PROCESS_RETURN} already exists" && exit 1
    echo 1 >"$PROCESS_RETURN" # Init lock with 1
    log_proc "${1}..."        # Log starting
}

process_run() {
    local pid="$1"              # Set process pid
    local process_name="$2"     # Set process name
    local user_canceled="false" # Will set to true if user press ctrl + c

    # Show gum spinner until pid is not exists anymore and set user_canceled to true on failure
    gum_spin --title " ${process_name}..." -- bash -c "while ps -p $pid &> /dev/null; do sleep 1; done" || user_canceled="true"
    cat "$PROCESS_LOG" >>"$SCRIPT_LOG" # Write process log to logfile

    # When user press ctrl + c while process is running
    if [ "$user_canceled" = "true" ]; then
        ps -p "$pid" &>/dev/null && kill "$pid"                                  # Kill process if running
        print_fail "Process with PID ${pid} was killed by user" && trap_gum_exit # Exit with 130
    fi

    # Handle error while executing process
    [ ! -f "$PROCESS_RETURN" ] && print_fail "${PROCESS_RETURN} not found (do not init process?)" && exit 1
    [ "$(<"$PROCESS_RETURN")" != "0" ] && print_fail "${process_name} failed" && exit 1 # If process failed (result code 0 was not write in the end)

    # Finish
    rm -f "$PROCESS_RETURN"                          # Remove process lock file
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
    local logo_gum && logo_gum='

  █████  ██████   ██████ ██   ██      ██████  ███████ 
 ██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
 ███████ ██████  ██      ███████     ██    ██ ███████ 
 ██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
 ██   ██ ██   ██  ██████ ██   ██      ██████  ███████

 '
    local title_gum && title_gum=$(gum_white --margin "1 0" --bold "Arch OS Installer ${VERSION}")
    clear && gum_purple --border normal --align "center" --padding "0 4" --border-foreground 247 "${logo_gum} ${title_gum}"
}

# Log
write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }

# Colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
gum_white() { gum style --foreground 255 "${@}"; }
gum_purple() { gum style --foreground 212 "${@}"; }
gum_green() { gum style --foreground 35 "${@}"; }
gum_yellow() { gum style --foreground 220 "${@}"; }
gum_red() { gum style --foreground 160 "${@}"; }
#gum_blue() { gum style --foreground 32 "${@}"; }

# Print
print_title() { gum_purple --bold --padding "1 1" "${*}"; }
print_info() { log_info "$*" && gum_green --bold " • ${*}"; }
print_warn() { log_warn "$*" && gum_yellow --bold " • ${*}"; }
print_fail() { log_fail "$*" && gum_red --bold " • ${*}"; }
print_add() { log_info "$*" && gum_green --bold " + ${*}"; }

# Gum
gum_confirm() { gum confirm --prompt.foreground 212 "${@}"; }
gum_input() { gum input --prompt " + " --prompt.foreground 212 "${@}"; }
gum_write() { gum write --prompt " • " --show-cursor-line --char-limit 0 "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground 212 --spinner.foreground 212 "${@}"; }

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
    } >"$SCRIPT_CONF" # Write properties to file
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_username() {
    if [ -z "$ARCH_OS_USERNAME" ]; then
        ARCH_OS_USERNAME=$(gum_input --placeholder="Please enter Username") || trap_gum_exit_confirm
        [ -z "${ARCH_OS_USERNAME}" ] && return 1 # Check if new value is null
        properties_generate                      # Generate properties file
    fi
    print_add "Username is set to ${ARCH_OS_USERNAME}"
}

# ----------------------------------------------------------------------------------------------------

select_password() {
    if [ "$1" = "--force" ] || [ -z "$ARCH_OS_PASSWORD" ]; then
        ARCH_OS_PASSWORD=$(gum_input --password --placeholder="Please enter Password") || trap_gum_exit_confirm
        [ -z "${ARCH_OS_PASSWORD}" ] && return 1 # Check if new value is null
        properties_generate                      # Generate properties file
    fi
    print_add "Password is set to *******"
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
    local process_name="Initialize Installation"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0
        # Check installation prerequisites
        [ ! -d /sys/firmware/efi ] && log_fail "BIOS not supported! Please set your boot mode to UEFI." && exit 1
        [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && log_fail "You must execute the Installer from Arch ISO!" && exit 1

        log_info "Waiting for Reflector from Arch ISO"
        # This mirrorlist will copied to new Arch system during installation
        while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
        pgrep reflector &>/dev/null && log_fail "Reflector timeout after 180 seconds" && exit 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_disk() {
    local process_name="Prepare Disk"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_bootloader() {
    local process_name="Install Bootloader"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_bootsplash() {
    local process_name="Install Bootsplash"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_aur_helper() {
    local process_name="Install AUR Helper"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &

    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_multilib() {
    local process_name="Enable Multilib"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_desktop() {
    local process_name="Install Desktop"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_shell_enhancement() {
    local process_name="Install Shell Enhancement"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_graphics_driver() {
    local process_name="Install Graphics Driver"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_vm_support() {
    local process_name="Install VM Support"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ----------------------------------------------------------------------------------------------------

exec_cleanup() {
    local process_name="Cleanup Installation"
    process_init "$process_name"
    (
        sleep 1
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_run $! "$process_name"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////////////  START MAIN  ///////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"
