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
        until select_encryption; do :; done
        until select_bootsplash; do :; done
        until select_variant; do :; done

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
    local header_logo='
 █████  ██████   ██████ ██   ██      ██████  ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
███████ ██████  ██      ███████     ██    ██ ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
██   ██ ██   ██  ██████ ██   ██      ██████  ███████
    ' && header_logo=$(gum_purple --bold "$header_logo")
    local header_title="Arch OS Installer ${VERSION}" && header_title=$(gum_white --bold "$header_title")
    local header_container && header_container=$(gum join --vertical --align center "$header_logo" "$header_title")
    clear && gum_style --align center --border none --border-foreground "$COLOR_WHITE" --margin 0 --padding "0 1" "$header_container"
}

# Log
write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }

# Colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }
gum_purple() { gum_style --foreground "$COLOR_PURPLE" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }

# Print
print_title() { gum_purple --margin "1 1" --bold "${*}"; }
print_info() { log_info "$*" && gum_green --bold " • ${*}"; }
print_warn() { log_warn "$*" && gum_yellow --bold " • ${*}"; }
print_fail() { log_fail "$*" && gum_red --bold " • ${*}"; }
print_add() { log_info "$*" && gum_green --bold " + ${*}"; }

# Gum
gum_style() { gum style "${@}"; } # Set default width
gum_confirm() { gum confirm --prompt.foreground "$COLOR_PURPLE" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt " + " --prompt.foreground "$COLOR_PURPLE" --header.foreground "$COLOR_PURPLE" "${@}"; }
gum_write() { gum write --prompt " • " --prompt.foreground "$COLOR_PURPLE" --header.foreground "$COLOR_PURPLE" --show-cursor-line --char-limit 0 "${@}"; }
gum_choose() { gum choose --cursor " > " --height 8 --header.foreground "$COLOR_PURPLE" --cursor.foreground "$COLOR_PURPLE" "${@}"; }
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
    [ -z "$ARCH_OS_SHELL_ENHANCED_ENABLED" ] && ARCH_OS_SHELL_ENHANCED_ENABLED="true"
    [ -z "$ARCH_OS_AUR_HELPER" ] && ARCH_OS_AUR_HELPER="paru"
    [ -z "$ARCH_OS_MULTILIB_ENABLED" ] && ARCH_OS_MULTILIB_ENABLED="true"
    [ -z "$ARCH_OS_ECN_ENABLED" ] && ARCH_OS_ECN_ENABLED="true"
    [ -z "$ARCH_OS_X11_KEYBOARD_MODEL" ] && ARCH_OS_X11_KEYBOARD_MODEL="pc105"
    [ -z "$ARCH_OS_X11_KEYBOARD_LAYOUT" ] && ARCH_OS_X11_KEYBOARD_LAYOUT="us"
    [ -z "$ARCH_OS_GRAPHICS_DRIVER" ] && ARCH_OS_GRAPHICS_DRIVER="mesa"
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
        options=() && for item in "${items[@]}"; do grep -q -e "$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
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
        [ -z "$user_input" ] && return 1      # Check if new value is null
        ARCH_OS_VCONSOLE_KEYMAP="$user_input" # Set property
        properties_generate                   # Generate properties file
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

select_encryption() {
    if [ -z "$ARCH_OS_ENCRYPTION_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable Encryption?" && user_input="true"
        ARCH_OS_ENCRYPTION_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Encryption is set to ${ARCH_OS_ENCRYPTION_ENABLED}"
}

# ----------------------------------------------------------------------------------------------------

select_bootsplash() {
    if [ -z "$ARCH_OS_BOOTSPLASH_ENABLED" ]; then
        local user_input="false" && gum_confirm "Enable Bootsplash?" && user_input="true"
        ARCH_OS_BOOTSPLASH_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    print_add "Bootsplash is set to ${ARCH_OS_BOOTSPLASH_ENABLED}"
}

# ----------------------------------------------------------------------------------------------------

select_variant() {
    if [ -z "$ARCH_OS_VARIANT" ] || [ -z "$ARCH_OS_GRAPHICS_DRIVER" ]; then
        local user_input options
        options=("desktop" "base" "core")
        user_input=$(gum_choose --header " + Choose Arch OS Variant" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        ARCH_OS_VARIANT="$user_input"    # Set property
        if [ "$ARCH_OS_VARIANT" = "desktop" ]; then
            options=("mesa" "intel_i915" "nvidia" "amd" "ati")
            user_input=$(gum_choose --header " + Choose Graphics Driver" "${options[@]}") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1      # Check if new value is null
            ARCH_OS_GRAPHICS_DRIVER="$user_input" # Set properties
        fi
        properties_generate # Generate properties file
    fi
    print_add "Variant is set to ${ARCH_OS_VARIANT}"
    [ "$ARCH_OS_VARIANT" = "desktop" ] && print_add "Graphics Driver is set to ${ARCH_OS_GRAPHICS_DRIVER}"
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# EXECUTORS (SUB PROCESSES)
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init() {
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
