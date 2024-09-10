#!/usr/bin/env bash
# shellcheck disable=SC1090

# ////////////////////////////////////////////////////////////////////////////////////////////////////
#                                          ARCH OS INSTALLER
#                                - Automated Arch Linux Installer TUI -
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# SOURCE:   https://github.com/murkl/arch-os
# AUTOR:    murkl
# ORIGIN:   Germany
# LICENCE:  GPL 2.0

# Debug simulator:  MODE=debug ./installer.sh
# Custom gum:       GUM=/usr/bin/gum ./installer.sh

# CONFIG
set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -e          # Terminate if any command exits with a non-zero
set -E          # ERR trap inherited by shell functions (errtrace)

# SCRIPT
VERSION='1.6.4'

# GUM
GUM_VERSION="0.13.0"

# ENVIRONMENT
SCRIPT_CONFIG="./installer.conf"
SCRIPT_LOG="./installer.log"

# TEMP
SCRIPT_TMP_DIR="$(mktemp -d "./.tmp.XXXXX")"
ERROR_MSG="${SCRIPT_TMP_DIR}/installer.err"
PROCESS_LOG="${SCRIPT_TMP_DIR}/process.log"
PROCESS_RET="${SCRIPT_TMP_DIR}/process.ret"

# COLORS
COLOR_WHITE=251
COLOR_GREEN=36
COLOR_PURPLE=212
COLOR_YELLOW=221
COLOR_RED=9

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Clear logfile
    [ -f "$SCRIPT_LOG" ] && mv -f "$SCRIPT_LOG" "${SCRIPT_LOG}.old"

    # Check gum binary or download
    gum_init

    # Traps (error & exit)
    trap 'trap_exit' EXIT
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

    # ---------------------------------------------------------------------------------------------------

    # Loop properties step to update screen if user edit properties
    while (true); do

        gum_header # Show welcome screen
        gum_white 'Please make sure you have:'
        echo
        gum_white '• Backed up your important data'
        gum_white '• A stable internet connection'
        gum_white '• Secure Boot disabled'
        gum_white '• Boot Mode set to UEFI'
        echo
        gum_title "Arch OS Properties"

        # Ask for load & remove existing config file
        if [ -f "$SCRIPT_CONFIG" ] && ! gum_confirm "Load existing installer.conf?"; then
            gum_confirm "Remove existing installer.conf?" || trap_gum_exit # If not want remove config -> exit script
            rm -f "$SCRIPT_CONFIG" && gum_info "installer.conf successfully removed"
            gum_warn "Please restart Arch OS Installer..."
            exit 0
        fi

        # Source installer.conf if exists
        properties_source && gum_info "installer.conf successfully loaded"

        # Selectors
        until select_preset; do :; done
        until select_username; do :; done
        until select_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_disk; do :; done
        until select_enable_encryption; do :; done
        until select_enable_core_tweaks; do :; done
        until select_enable_bootsplash; do :; done
        until select_enable_multilib; do :; done
        until select_enable_aur; do :; done
        until select_enable_housekeeping; do :; done
        until select_enable_shell_enhancement; do :; done
        until select_enable_manager; do :; done
        until select_enable_desktop; do :; done

        # Print success
        gum_info "installer.conf successfully initialized"

        # Edit properties?
        if gum_confirm "Edit installer.conf manually?"; then
            log_info "Edit installer.conf manually..."
            local gum_header="Save with CTRL + D or ESC and cancel with CTRL + C"
            if gum_write --height=10 --width=100 --header=" ${gum_header}" --value="$(cat "$SCRIPT_CONFIG")" >"${SCRIPT_CONFIG}.new"; then
                mv "${SCRIPT_CONFIG}.new" "${SCRIPT_CONFIG}" && properties_source
                gum_info "installer.conf successfully edited"
                gum_confirm "Change Password?" && until select_password --force && properties_source; do :; done
                gum_spin --title="Reload Properties in 3 seconds..." -- sleep 3 || trap_gum_exit
                continue # Restart properties step to refresh properties screen
            else
                rm -f "${SCRIPT_CONFIG}.new" # Remove tmp properties
                gum_warn "Canceled"
            fi
        fi

        ######################################################
        break # Exit properties step and continue installation
        ######################################################
    done

    # ---------------------------------------------------------------------------------------------------

    # Start installation in 5 seconds?
    gum_confirm "Start Arch OS Installation?" || trap_gum_exit
    echo && gum_title "Arch OS Installation"
    local spin_title="Arch OS Installation starts in 5 seconds. Press CTRL + C to cancel..."
    gum_spin --title="$spin_title" -- sleep 5 || trap_gum_exit # CTRL + C pressed

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
    exec_install_archos_manager
    exec_install_vm_support
    exec_cleanup_installation

    # Calc installation duration
    duration=$SECONDS # This is set before install starts
    duration_min="$((duration / 60))"
    duration_sec="$((duration % 60))"

    # Print duration time info
    local finish_txt="Installation successful in ${duration_min} minutes and ${duration_sec} seconds"
    echo && gum_green --bold "$finish_txt"
    log_info "$finish_txt"

    # Copy installer files to users home
    if [ "$MODE" != "debug" ]; then
        cp -f "$SCRIPT_CONFIG" "/mnt/home/${ARCH_OS_USERNAME}/installer.conf"
        cp -f "$SCRIPT_LOG" "/mnt/home/${ARCH_OS_USERNAME}/installer.log"
        arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}/installer.conf"
        arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}/installer.log"
    fi

    wait # Wait for sub processes

    # ---------------------------------------------------------------------------------------------------

    # Show reboot & unmount promt
    local do_reboot="false"
    local do_unmount="false"
    gum_confirm "Reboot to Arch OS now?" && do_reboot="true" && do_unmount="true"
    [ "$do_reboot" = "false" ] && gum_confirm "Unmount Arch OS from /mnt?" && do_unmount="true"

    # Unmount
    if [ "$do_unmount" = "true" ] && [ "$MODE" != "debug" ]; then
        swapoff -a
        umount -A -R /mnt
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot
    fi

    # Reboot
    [ "$do_reboot" = "true" ] && [ "$MODE" != "debug" ] && gum_warn "Rebooting..." && reboot

    exit 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROPERTIES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

properties_source() {
    [ ! -f "$SCRIPT_CONFIG" ] && return 1
    set -a # Load properties file and auto export variables
    source "$SCRIPT_CONFIG"
    set +a
    return 0
}

properties_generate() {
    { # Write properties to installer.conf
        echo "ARCH_OS_HOSTNAME='${ARCH_OS_HOSTNAME}'"
        echo "ARCH_OS_USERNAME='${ARCH_OS_USERNAME}'"
        echo "ARCH_OS_DISK='${ARCH_OS_DISK}'"
        echo "ARCH_OS_BOOT_PARTITION='${ARCH_OS_BOOT_PARTITION}'"
        echo "ARCH_OS_ROOT_PARTITION='${ARCH_OS_ROOT_PARTITION}'"
        echo "ARCH_OS_ENCRYPTION_ENABLED='${ARCH_OS_ENCRYPTION_ENABLED}'"
        echo "ARCH_OS_TIMEZONE='${ARCH_OS_TIMEZONE}'"
        echo "ARCH_OS_LOCALE_LANG='${ARCH_OS_LOCALE_LANG}'"
        echo "ARCH_OS_LOCALE_GEN_LIST=(${ARCH_OS_LOCALE_GEN_LIST[*]@Q})"
        echo "ARCH_OS_REFLECTOR_COUNTRY='${ARCH_OS_REFLECTOR_COUNTRY}'"
        echo "ARCH_OS_VCONSOLE_KEYMAP='${ARCH_OS_VCONSOLE_KEYMAP}'"
        echo "ARCH_OS_VCONSOLE_FONT='${ARCH_OS_VCONSOLE_FONT}'"
        echo "ARCH_OS_KERNEL='${ARCH_OS_KERNEL}'"
        echo "ARCH_OS_MICROCODE='${ARCH_OS_MICROCODE}'"
        echo "ARCH_OS_CORE_TWEAKS_ENABLED='${ARCH_OS_CORE_TWEAKS_ENABLED}'"
        echo "ARCH_OS_MULTILIB_ENABLED='${ARCH_OS_MULTILIB_ENABLED}'"
        echo "ARCH_OS_AUR_HELPER='${ARCH_OS_AUR_HELPER}'"
        echo "ARCH_OS_BOOTSPLASH_ENABLED='${ARCH_OS_BOOTSPLASH_ENABLED}'"
        echo "ARCH_OS_SHELL_ENHANCEMENT_ENABLED='${ARCH_OS_SHELL_ENHANCEMENT_ENABLED}'"
        echo "ARCH_OS_SHELL_ENHANCEMENT_FISH_ENABLED='${ARCH_OS_SHELL_ENHANCEMENT_FISH_ENABLED}'"
        echo "ARCH_OS_HOUSEKEEPING_ENABLED='${ARCH_OS_HOUSEKEEPING_ENABLED}'"
        echo "ARCH_OS_MANAGER_ENABLED='${ARCH_OS_MANAGER_ENABLED}'"
        echo "ARCH_OS_DESKTOP_ENABLED='${ARCH_OS_DESKTOP_ENABLED}'"
        echo "ARCH_OS_DESKTOP_SLIM_ENABLED='${ARCH_OS_DESKTOP_SLIM_ENABLED}'"
        echo "ARCH_OS_DESKTOP_GRAPHICS_DRIVER='${ARCH_OS_DESKTOP_GRAPHICS_DRIVER}'"
        echo "ARCH_OS_DESKTOP_KEYBOARD_LAYOUT='${ARCH_OS_DESKTOP_KEYBOARD_LAYOUT}'"
        echo "ARCH_OS_DESKTOP_KEYBOARD_MODEL='${ARCH_OS_DESKTOP_KEYBOARD_MODEL}'"
        echo "ARCH_OS_DESKTOP_KEYBOARD_VARIANT='${ARCH_OS_DESKTOP_KEYBOARD_VARIANT}'"
        echo "ARCH_OS_VM_SUPPORT_ENABLED='${ARCH_OS_VM_SUPPORT_ENABLED}'"
        echo "ARCH_OS_ECN_ENABLED='${ARCH_OS_ECN_ENABLED}'"
    } >"$SCRIPT_CONFIG" # Write properties to file
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_preset() {
    if [ ! -f "$SCRIPT_CONFIG" ]; then
        local preset options
        options=("desktop" "core" "custom")
        preset=$(gum_choose --header "+ Choose Preset:" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$preset" ] && return 1 # Check if new value is null

        # Default presets
        ARCH_OS_HOSTNAME="arch-os"
        ARCH_OS_KERNEL="linux-zen"
        ARCH_OS_VM_SUPPORT_ENABLED="true"
        ARCH_OS_SHELL_ENHANCEMENT_FISH_ENABLED="true"
        ARCH_OS_ECN_ENABLED="true"
        ARCH_OS_DESKTOP_KEYBOARD_MODEL="pc105"

        # Set microcode
        grep -E "GenuineIntel" &>/dev/null <<<"$(lscpu)" && ARCH_OS_MICROCODE="intel-ucode"
        grep -E "AuthenticAMD" &>/dev/null <<<"$(lscpu)" && ARCH_OS_MICROCODE="amd-ucode"

        # Core preset
        if [ "$preset" = "core" ]; then
            ARCH_OS_DESKTOP_ENABLED='false'
            ARCH_OS_MULTILIB_ENABLED='false'
            ARCH_OS_HOUSEKEEPING_ENABLED='false'
            ARCH_OS_SHELL_ENHANCEMENT_ENABLED='false'
            ARCH_OS_AUR_HELPER='none'
            ARCH_OS_MANAGER_ENABLED='false'
            ARCH_OS_DESKTOP_GRAPHICS_DRIVER="none"
        fi

        # Desktop preset
        if [ "$preset" = "desktop" ]; then
            ARCH_OS_CORE_TWEAKS_ENABLED="true"
            ARCH_OS_BOOTSPLASH_ENABLED='true'
            ARCH_OS_DESKTOP_ENABLED='true'
            ARCH_OS_MULTILIB_ENABLED='true'
            ARCH_OS_HOUSEKEEPING_ENABLED='true'
            ARCH_OS_SHELL_ENHANCEMENT_ENABLED='true'
            ARCH_OS_AUR_HELPER='paru-bin'
            ARCH_OS_MANAGER_ENABLED='true'
        fi

        # Write properties
        properties_generate && gum_info "Preset is set to ${preset}"
    fi
}

# ---------------------------------------------------------------------------------------------------

select_username() {
    if [ -z "$ARCH_OS_USERNAME" ]; then
        local user_input
        user_input=$(gum_input --header "+ Enter Username (mandatory)") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                      # Check if new value is null
        ARCH_OS_USERNAME="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Username is set to ${ARCH_OS_USERNAME}"
}

# ---------------------------------------------------------------------------------------------------

select_password() { # --force
    if [ "$1" = "--force" ] || [ -z "$ARCH_OS_PASSWORD" ]; then
        local user_password user_password_check
        user_password=$(gum_input --password --header "+ Enter Password (mandatory)") || trap_gum_exit_confirm
        [ -z "$user_password" ] && return 1 # Check if new value is null
        user_password_check=$(gum_input --password --header "+ Enter Password again") || trap_gum_exit_confirm
        [ -z "$user_password_check" ] && return 1 # Check if new value is null
        [ "$user_password" != "$user_password_check" ] && gum_fail "Passwords not identical" && return 1
        ARCH_OS_PASSWORD="$user_password" && properties_generate # Set value and generate properties file
    fi
    gum_info "Password is set to *******"
}

# ---------------------------------------------------------------------------------------------------

select_timezone() {
    if [ -z "$ARCH_OS_TIMEZONE" ]; then
        local tz_auto user_input
        tz_auto="$(curl -s http://ip-api.com/line?fields=timezone)"
        user_input=$(gum_input --header "+ Enter Timezone (auto)" --value "$tz_auto") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        [ ! -f "/usr/share/zoneinfo/${user_input}" ] && gum_fail "Timezone '${user_input}' is not supported" && return 1
        ARCH_OS_TIMEZONE="$user_input" && properties_generate # Set property and generate properties file
    fi
    gum_info "Timezone is set to ${ARCH_OS_TIMEZONE}"
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2001
select_language() {
    if [ -z "$ARCH_OS_LOCALE_LANG" ] || [ -z "${ARCH_OS_LOCALE_GEN_LIST[*]}" ]; then
        local user_input items options filter
        # Fetch available options (list all from /usr/share/i18n/locales and check if entry exists in /etc/locale.gen)
        mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@") # Create array without @ files
        # Add only available locales (!!! intense command !!!)
        options=() && for item in "${items[@]}"; do grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        # Select locale
        user_input=$(gum_filter --value="$filter" --header "+ Choose Language" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1  # Check if new value is null
        ARCH_OS_LOCALE_LANG="$user_input" # Set property
        # Set locale.gen properties (auto generate ARCH_OS_LOCALE_GEN_LIST)
        ARCH_OS_LOCALE_GEN_LIST=() && while read -r locale_entry; do
            ARCH_OS_LOCALE_GEN_LIST+=("$locale_entry")
            # Remove leading # from matched lang in /etc/locale.gen and add entry to array
        done < <(sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "$ARCH_OS_LOCALE_LANG")
        # Add en_US fallback (every language) if not already exists in list
        [[ "${ARCH_OS_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && ARCH_OS_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')
        properties_generate # Generate properties file (for ARCH_OS_LOCALE_LANG & ARCH_OS_LOCALE_GEN_LIST)
    fi
    gum_info "Language is set to ${ARCH_OS_LOCALE_LANG}"
}

# ---------------------------------------------------------------------------------------------------

select_keyboard() {
    if [ -z "$ARCH_OS_VCONSOLE_KEYMAP" ]; then
        local user_input items options filter
        mapfile -t items < <(command localectl list-keymaps)
        options=() && for item in "${items[@]}"; do options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        user_input=$(gum_filter --value="$filter" --header "+ Choose Keyboard" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                             # Check if new value is null
        ARCH_OS_VCONSOLE_KEYMAP="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Keyboard is set to ${ARCH_OS_VCONSOLE_KEYMAP}"
}

# ---------------------------------------------------------------------------------------------------

select_disk() {
    if [ -z "$ARCH_OS_DISK" ] || [ -z "$ARCH_OS_BOOT_PARTITION" ] || [ -z "$ARCH_OS_ROOT_PARTITION" ]; then
        local user_input items options
        mapfile -t items < <(lsblk -I 8,259,254 -d -o KNAME,SIZE -n)
        # size: $(lsblk -d -n -o SIZE "/dev/${item}")
        options=() && for item in "${items[@]}"; do options+=("/dev/${item}"); done
        user_input=$(gum_choose --header "+ Choose Disk" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                          # Check if new value is null
        user_input=$(echo "$user_input" | awk -F' ' '{print $1}') # Remove size from input
        [ ! -e "$user_input" ] && log_fail "Disk does not exists" && return 1
        ARCH_OS_DISK="$user_input" # Set property
        [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}p1" || ARCH_OS_BOOT_PARTITION="${ARCH_OS_DISK}1"
        [[ "$ARCH_OS_DISK" = "/dev/nvm"* ]] && ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}p2" || ARCH_OS_ROOT_PARTITION="${ARCH_OS_DISK}2"
        properties_generate # Generate properties file
    fi
    gum_info "Disk is set to ${ARCH_OS_DISK}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_encryption() {
    if [ -z "$ARCH_OS_ENCRYPTION_ENABLED" ]; then
        gum_confirm "Enable Disk Encryption?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_ENCRYPTION_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Disk Encryption is set to ${ARCH_OS_ENCRYPTION_ENABLED}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_core_tweaks() {
    if [ -z "$ARCH_OS_CORE_TWEAKS_ENABLED" ]; then
        gum_confirm "Enable Core Tweaks?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_CORE_TWEAKS_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Core Tweaks is set to ${ARCH_OS_CORE_TWEAKS_ENABLED}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_bootsplash() {
    if [ -z "$ARCH_OS_BOOTSPLASH_ENABLED" ]; then
        gum_confirm "Enable Bootsplash?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_BOOTSPLASH_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Bootsplash is set to ${ARCH_OS_BOOTSPLASH_ENABLED}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop() {
    local user_input options

    # Select desktop environment
    if [ -z "$ARCH_OS_DESKTOP_ENABLED" ]; then
        gum_confirm "Enable Desktop Environment?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_DESKTOP_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Desktop Environment is set to ${ARCH_OS_DESKTOP_ENABLED}"
    # Return if desktop disabled
    [ "$ARCH_OS_DESKTOP_ENABLED" = "false" ] && return 0

    # Slim Mode
    if [ -z "$ARCH_OS_DESKTOP_SLIM_ENABLED" ]; then
        gum_confirm "Enable Desktop Slim Mode? (GNOME Core Apps only)" --affirmative="No (default)" --negative="Yes"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        [ $user_confirm = 1 ] && user_input="true"
        [ $user_confirm = 0 ] && user_input="false"
        ARCH_OS_DESKTOP_SLIM_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Desktop Slim Mode is set to ${ARCH_OS_DESKTOP_SLIM_ENABLED}"

    # Keyboard layout
    if [ -z "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" ]; then
        user_input=$(gum_input --header "+ Enter Desktop Keyboard Layout (mandatory)" --placeholder "e.g. 'us' or 'de'...") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="$user_input"
        user_input=$(gum_input --header "+ Enter Desktop Keyboard Variant (optional)" --placeholder "e.g. 'nodeadkeys' or leave empty...") || trap_gum_exit_confirm
        ARCH_OS_DESKTOP_KEYBOARD_VARIANT="$user_input"
        properties_generate
    fi
    gum_info "Desktop Keyboard Layout is set to ${ARCH_OS_DESKTOP_KEYBOARD_LAYOUT}"
    [ -n "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT" ] && gum_info "Desktop Keyboard Variant is set to ${ARCH_OS_DESKTOP_KEYBOARD_VARIANT}"

    # Graphics driver
    if [ -z "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" ] || [ "$ARCH_OS_DESKTOP_GRAPHICS_DRIVER" = "none" ]; then
        options=("mesa" "intel_i915" "nvidia" "amd" "ati")
        user_input=$(gum_choose --header "+ Choose Desktop Graphics Driver (default: mesa)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                                     # Check if new value is null
        ARCH_OS_DESKTOP_GRAPHICS_DRIVER="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Desktop Graphics Driver is set to ${ARCH_OS_DESKTOP_GRAPHICS_DRIVER}"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_aur() {
    if [ -z "$ARCH_OS_AUR_HELPER" ]; then
        gum_confirm "Enable AUR Helper?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="none"
        [ $user_confirm = 0 ] && user_input="paru-bin"
        ARCH_OS_AUR_HELPER="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "AUR Helper is set to ${ARCH_OS_AUR_HELPER}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_multilib() {
    if [ -z "$ARCH_OS_MULTILIB_ENABLED" ]; then
        gum_confirm "Enable 32 Bit Support?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_MULTILIB_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "32 Bit Support is set to ${ARCH_OS_MULTILIB_ENABLED}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_housekeeping() {
    if [ -z "$ARCH_OS_HOUSEKEEPING_ENABLED" ]; then
        gum_confirm "Enable Housekeeping?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_HOUSEKEEPING_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Housekeeping is set to ${ARCH_OS_HOUSEKEEPING_ENABLED}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_shell_enhancement() {
    if [ -z "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" ]; then
        gum_confirm "Enable Shell Enhancement?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_SHELL_ENHANCEMENT_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Shell Enhancement is set to ${ARCH_OS_SHELL_ENHANCEMENT_ENABLED}"
}

# ---------------------------------------------------------------------------------------------------

select_enable_manager() {
    if [ -z "$ARCH_OS_MANAGER_ENABLED" ]; then
        gum_confirm "Enable Arch OS Manager?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_MANAGER_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_info "Arch OS Manager is set to ${ARCH_OS_MANAGER_ENABLED}"
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
        bootctl status | grep "Secure Boot" | grep -q "disabled" || { log_fail "You must disable Secure Boot in UEFI to continue installation" && exit 1; }
        log_info "Secure Boot: disabled"
        [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && log_fail "You must execute the Installer from Arch ISO!" && exit 1
        log_info "Arch ISO detected"
        log_info "Waiting for Reflector from Arch ISO..."
        # This mirrorlist will copied to new Arch system during installation
        while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
        pgrep reflector &>/dev/null && log_fail "Reflector timeout after 180 seconds" && exit 1
        rm -f /var/lib/pacman/db.lck # Remove pacman lock file if exists
        timedatectl set-ntp true     # Set time
        # Make sure everything is unmounted before start install
        swapoff -a || true
        if [[ "$(umount -f -A -R /mnt 2>&1)" == *"target is busy"* ]]; then
            # If umount is busy execute fuser
            fuser -km /mnt || true
            umount -f -A -R /mnt || true
        fi
        wait # Wait for sub process
        cryptsetup close cryptroot || true
        vgchange -an || true
        # Temporarily disable ECN (prevent traffic problems with some old routers)
        [ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0
        pacman -Sy --noconfirm archlinux-keyring # Update keyring
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_prepare_disk() {
    local process_name="Prepare Disk"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return

        # Wipe and create partitions
        wipefs -af "$ARCH_OS_DISK"                                        # Remove All Filesystem Signatures
        sgdisk --zap-all "$ARCH_OS_DISK"                                  # Remove the Partition Table
        sgdisk -o "$ARCH_OS_DISK"                                         # Create new GPT partition table
        sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_OS_DISK" # Create partition /boot efi partition: 1 GiB
        sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$ARCH_OS_DISK"   # Create partition / partition: Rest of space
        partprobe "$ARCH_OS_DISK"                                         # Reload partition table

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
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_pacstrap_core() {
    local process_name="Pacstrap Arch OS Core System"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return

        # Core packages
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
        # https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
        # https://wiki.archlinux.org/title/Microcode#mkinitcpio
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect microcode modconf sd-vconsole block sd-encrypt filesystems fsck)/" /mnt/etc/mkinitcpio.conf
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect microcode modconf sd-vconsole block filesystems fsck)/" /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P

        # Install Bootloader to /boot (systemdboot)
        arch-chroot /mnt bootctl --esp-path=/boot install # Install systemdboot to /boot

        # Kernel args
        # Zswap should be disabled when using zram (https://github.com/archlinux/archinstall/issues/881)
        # Silent boot: https://wiki.archlinux.org/title/Silent_boot
        local kernel_args=()
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && kernel_args+=("rd.luks.name=$(blkid -s UUID -o value "${ARCH_OS_ROOT_PARTITION}")=cryptroot" "root=/dev/mapper/cryptroot")
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && kernel_args+=("root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_OS_ROOT_PARTITION}")")
        kernel_args+=('rw' 'init=/usr/lib/systemd/systemd' 'zswap.enabled=0')
        [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ] && kernel_args+=('nowatchdog')
        [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ] && kernel_args+=('quiet' 'splash' 'vt.global_cursor_default=0')

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
            echo "initrd  /initramfs-${ARCH_OS_KERNEL}.img"
            echo "options ${kernel_args[*]}"
        } >/mnt/boot/loader/entries/arch.conf

        # Create fallback boot entry
        {
            echo 'title   Arch OS (Fallback)'
            echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
            echo "initrd  /initramfs-${ARCH_OS_KERNEL}-fallback.img"
            echo "options ${kernel_args[*]}"
        } >/mnt/boot/loader/entries/arch-fallback.conf

        # Create new user
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"

        # Create user dirs
        mkdir -p "/mnt/home/${ARCH_OS_USERNAME}/.config"
        mkdir -p "/mnt/home/${ARCH_OS_USERNAME}/.local/share"
        arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"

        # Allow users in group wheel to use sudo
        sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers

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

        # Make some Arch OS tweaks
        if [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ]; then

            # Add password feedback
            echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers

            # Configure pacman parrallel downloads, colors, eyecandy
            sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
            sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf

            # Disable watchdog modules
            mkdir -p /mnt/etc/modprobe.d/
            echo 'blacklist sp5100_tco' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf
            echo 'blacklist iTCO_wdt' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf

            # Set max VMAs (need for some apps/games)
            #echo vm.max_map_count=1048576 >/mnt/etc/sysctl.d/vm.max_map_count.conf

            # Reduce shutdown timeout
            #sed -i "s/^\s*#\s*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf
        fi

        # Return
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_install_desktop() {
    local process_name="Install Desktop Environment"
    if [ "$ARCH_OS_DESKTOP_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0 # If debug mode then return

            # GNOME base packages
            local packages=(gnome gnome-tweaks gnome-browser-connector gnome-themes-extra power-profiles-daemon rygel cups gnome-epub-thumbnailer)
            [ "$ARCH_OS_DESKTOP_SLIM_ENABLED" = "false" ] && packages+=(gnome-firmware file-roller)

            # GNOME wayland screensharing, flatpak & pipewire support
            packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome flatpak-xdg-utils)

            # Audio (Pipewire replacements + session manager)
            packages+=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber)
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

            # Networking & Access
            packages+=(samba gvfs gvfs-mtp gvfs-smb gvfs-nfs gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-google gvfs-dnssd gvfs-wsdd)

            # Utils (https://wiki.archlinux.org/title/File_systems)
            packages+=(fwupd bash-completion git dhcp net-tools inetutils nfs-utils f2fs-tools udftools dosfstools ntfs-3g exfat-utils p7zip zip unzip unrar tar)

            # Certificates
            packages+=(ca-certificates)

            # Codecs (https://wiki.archlinux.org/title/Codecs_and_containers)
            packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss libheif webp-pixbuf-loader)
            packages+=(a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore libdvdnav libdvdread openh264)
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gstreamer lib32-gst-plugins-good)

            # Optimization
            packages+=(gamemode)
            [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

            # Fonts
            packages+=(noto-fonts noto-fonts-emoji ttf-firacode-nerd ttf-liberation ttf-dejavu)

            # Theming
            packages+=(adw-gtk-theme)

            # Install packages
            chroot_pacman_install "${packages[@]}"

            # Force remove packages
            if [ "$ARCH_OS_DESKTOP_SLIM_ENABLED" = "true" ]; then
                chroot_pacman_remove gnome-calendar || true
                chroot_pacman_remove gnome-maps || true
                chroot_pacman_remove gnome-contacts || true
                chroot_pacman_remove gnome-font-viewer || true
                chroot_pacman_remove gnome-characters || true
                chroot_pacman_remove gnome-clocks || true
                chroot_pacman_remove gnome-connections || true
                chroot_pacman_remove gnome-music || true
                chroot_pacman_remove gnome-weather || true
                chroot_pacman_remove gnome-calculator || true
                chroot_pacman_remove gnome-logs || true
                chroot_pacman_remove gnome-text-editor || true
                chroot_pacman_remove gnome-disk-utility || true
                chroot_pacman_remove simple-scan || true
                chroot_pacman_remove baobab || true
                chroot_pacman_remove totem || true
                chroot_pacman_remove snapshot || true
                chroot_pacman_remove loupe || true
                chroot_pacman_remove epiphany || true
                #chroot_pacman_remove evince || true # Need for sushi
            fi

            # Add user to gamemode group
            arch-chroot /mnt gpasswd -a "$ARCH_OS_USERNAME" gamemode

            # Enable GNOME auto login
            mkdir -p /mnt/etc/gdm
            [ -f /mnt/etc/gdm/custom.conf ] && mv /mnt/etc/gdm/custom.conf /mnt/etc/gdm/custom.conf.bak
            #grep -qrnw /mnt/etc/gdm/custom.conf -e "AutomaticLoginEnable" || sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${ARCH_OS_USERNAME}\n\n\[security\]/g" /mnt/etc/gdm/custom.conf
            {
                echo "[daemon]"
                echo "WaylandEnable=True"
                echo ""
                echo "AutomaticLoginEnable=True"
                echo "AutomaticLogin=${ARCH_OS_USERNAME}"
                echo ""
                echo "[debug]"
                echo "Enable=False"
            } >/mnt/etc/gdm/custom.conf

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
                echo 'PATH="${PATH}:/var/lib/flatpak/exports/bin"'
                echo ''
                echo '# XDG'
                echo 'XDG_CONFIG_HOME="${HOME}/.config"'
                echo 'XDG_DATA_HOME="${HOME}/.local/share"'
                echo 'XDG_STATE_HOME="${HOME}/.local/state"'
                echo 'XDG_CACHE_HOME="${HOME}/.cache"                '
            } >"/mnt/home/${ARCH_OS_USERNAME}/.config/environment.d/00-arch.conf"

            # Samba
            mkdir -p "/mnt/etc/samba/"
            {
                echo "[global]"
                echo "   workgroup = WORKGROUP"
                echo "   log file = /var/log/samba/%m"
            } >/mnt/etc/samba/smb.conf

            # Set X11 keyboard layout in /etc/X11/xorg.conf.d/00-keyboard.conf
            mkdir -p /mnt/etc/X11/xorg.conf.d/
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
            arch-chroot /mnt systemctl enable power-profiles-daemon                                                    # Power daemon
            arch-chroot /mnt systemctl enable cups.socket                                                              # Printer
            arch-chroot /mnt systemctl enable smb.service                                                              # Samba
            arch-chroot /mnt systemctl enable nmb.service                                                              # Samba
            arch-chroot /mnt systemctl enable gpm.service                                                              # TTY Mouse Support
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire.service       # Pipewire
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire-pulse.service # Pipewire
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user wireplumber.service    # Pipewire
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user gcr-ssh-agent.socket   # GCR ssh-agent

            # Create users applications dir
            mkdir -p "/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications"

            # Create UEFI Boot desktop entry
            #{
            #    echo '[Desktop Entry]'
            #    echo 'Name=Reboot to UEFI'
            #    echo 'Icon=system-reboot'
            #    echo 'Exec=systemctl reboot --firmware-setup'
            #    echo 'Type=Application'
            #    echo 'Terminal=false'
            #} >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/systemctl-reboot-firmware.desktop"

            # Hide desktop Aaplications icons
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
            if [ "$ARCH_OS_MANAGER_ENABLED" = "true" ]; then
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_OS_USERNAME}/.local/share/applications/kitty.desktop"
            fi

            # Set correct permissions
            arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"

            # Return
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_graphics_driver() {
    local process_name="Install Desktop Graphics Driver"
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
                #sed -i "s/systemd zswap.enabled=0/systemd nvidia_drm.modeset=1 nvidia_drm.fbdev=1 zswap.enabled=0/g" /mnt/boot/loader/entries/arch.conf
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
                local packages=(mesa mesa-utils xf86-video-amdgpu vulkan-radeon libva-mesa-driver mesa-vdpau vkd3d)
                [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-vulkan-radeon lib32-libva-mesa-driver lib32-mesa-vdpau lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # Must be discussed: https://wiki.archlinux.org/title/AMDGPU#Disable_loading_radeon_completely_at_boot
                sed -i "s/^MODULES=(.*)/MODULES=(amdgpu)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "ati") # https://wiki.archlinux.org/title/ATI#Installation
                local packages=(mesa mesa-utils xf86-video-ati libva-mesa-driver mesa-vdpau vkd3d)
                [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-libva-mesa-driver lib32-mesa-vdpau lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            esac
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

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
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

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
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

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
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_housekeeping() {
    local process_name="Install Housekeeping"
    if [ "$ARCH_OS_HOUSEKEEPING_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0                            # If debug mode then return
            chroot_pacman_install pacman-contrib reflector pkgfile smartmontools irqbalance # Install Base packages
            {                                                                               # Configure reflector service
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
            arch-chroot /mnt systemctl enable smartd               # SMART check service (smartmontools)
            arch-chroot /mnt systemctl enable irqbalance.service   # IRQ balancing daemon (irqbalance)
            process_return 0                                       # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_archos_manager() {
    local process_name="Install Arch OS Manager"
    if [ "$ARCH_OS_MANAGER_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0                    # If debug mode then return
            chroot_pacman_install git base-devel kitty gum libnotify pacman-contrib # Install dependencies
            chroot_aur_install arch-os-manager                                      # Install archos-manager
            process_return 0                                                        # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_shell_enhancement() {
    local process_name="Install Shell Enhancement"
    if [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$MODE" = "debug" ] && sleep 1 && process_return 0                                     # If debug mode then return
            chroot_pacman_install starship eza bat fastfetch mc btop nano man-db bash-completion     # Install packages
            mkdir -p "/mnt/root/.config/fastfetch" "/mnt/home/${ARCH_OS_USERNAME}/.config/fastfetch" # Create fastfetch config dirs

            # Install & set fish for root & user
            if [ "$ARCH_OS_SHELL_ENHANCEMENT_FISH_ENABLED" = "true" ]; then
                chroot_pacman_install fish
                mkdir -p "/mnt/root/.config/fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish" # Create fish config dirs
                # shellcheck disable=SC2016
                { # Create fish config for root & user
                    echo 'if status is-interactive'
                    echo '    # Commands to run in interactive sessions can go here'
                    echo 'end'
                    echo ''
                    echo '# Export environment variables'
                    echo 'if status --is-login'
                    echo '  for line in (/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator)'
                    echo '      set -gx (echo $line | cut -d= -f1) (echo $line | cut -d= -f2-)'
                    echo '  end'
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
                    echo 'source "$HOME/.aliases"'
                    echo ''
                    echo '# Source starship promt'
                    echo 'starship init fish | source'
                } | tee "/mnt/root/.config/fish/config.fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish/config.fish" >/dev/null
                arch-chroot /mnt chsh -s /usr/bin/fish
                arch-chroot /mnt chsh -s /usr/bin/fish "$ARCH_OS_USERNAME"
            fi

            { # Create aliases for root & user
                echo 'alias ls="eza --color=always --group-directories-first"'
                echo 'alias ll="ls -l"'
                echo 'alias la="ls -la"'
                echo 'alias lt="ls -Tal"'
                echo 'alias diff="diff --color=auto"'
                echo 'alias grep="grep --color=auto"'
                echo 'alias ip="ip -color=auto"'
                echo 'alias open="xdg-open"'
                echo 'alias fetch="fastfetch"'
                echo 'alias logs="systemctl --failed; echo; journalctl -p 3 -b"'
                echo 'alias q="exit"'
                echo 'alias .="cd .."'
                echo 'alias ..="cd ../.."'
                echo 'alias ...="cd ../../.."'
            } | tee "/mnt/root/.aliases" "/mnt/home/${ARCH_OS_USERNAME}/.aliases" >/dev/null

            # shellcheck disable=SC2016
            { # Create bash config for root & user
                echo '# If not running interactively, do not do anything'
                echo '[[ $- != *i* ]] && return'
                echo ''
                echo ' # Export systemd environment vars from ~/.config/environment.d/* (tty only)'
                echo '[ -z "$DISPLAY" ] && export $(/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator | xargs)'
                echo ''
                echo '# Source aliases'
                echo 'source "${HOME}/.aliases"'
                echo ''
                echo '# Plugin: pkgfile (command not found)'
                echo '[ -f /usr/share/doc/pkgfile/command-not-found.bash ] && source /usr/share/doc/pkgfile/command-not-found.bash'
                echo ''
                echo '# Options'
                echo 'shopt -s autocd                  # Auto cd'
                echo 'shopt -s cdspell                 # Correct cd typos'
                echo 'shopt -s checkwinsize            # Update windows size on command'
                echo 'shopt -s histappend              # Append History instead of overwriting file'
                echo 'shopt -s cmdhist                 # Bash attempts to save all lines of a multiple-line command in the same history entry'
                echo 'shopt -s extglob                 # Extended pattern'
                echo 'shopt -s no_empty_cmd_completion # No empty completion'
                echo 'shopt -s expand_aliases          # Expand aliases'
                echo ''
                echo '# Ignore upper and lowercase when TAB completion'
                echo 'bind "set completion-ignore-case on"'
                echo ''
                echo '# Colorize man pages (bat)'
                echo -n 'export MANPAGER="sh -c ' && echo -n "'col -bx | bat -l man -p'" && echo '"'
                echo 'export MANROFFOPT="-c"'
                echo ''
                echo '# Colorize help (usage: help <command>)'
                echo 'help() { "$@" --help 2>&1 | bat --plain --language=help; } '
                echo ''
                echo '# History'
                echo 'export HISTSIZE=1000                    # History will save N commands'
                echo 'export HISTFILESIZE=${HISTSIZE}         # History will remember N commands'
                echo 'export HISTCONTROL=ignoredups:erasedups # Ingore duplicates and spaces (ignoreboth)'
                echo 'export HISTTIMEFORMAT="%F %T "          # Add date to history'
                echo ''
                echo '# History ignore list'
                echo 'export HISTIGNORE=' &
                echo 'export HISTIGNORE="&:ls:ll:la:cd:exit:clear:history:q"'
                echo ''
                echo '# Set starship'
                echo 'command -v starship &>/dev/null && eval "$(starship init bash)"'

            } | tee "/mnt/root/.bashrc" "/mnt/home/${ARCH_OS_USERNAME}/.bashrc" >/dev/null

            # shellcheck disable=SC2016
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
                echo "[directory]"
                echo "style = 'bold green'"
                echo ""
                echo "# Replace the promt symbol"
                echo "[character]"
                echo "success_symbol = '[>](bold purple)'"
                echo ""
                echo "# Disable the package module, hiding it from the prompt completely"
                echo "[package]"
                echo "disabled = true"
                echo ""
                echo '[shell]'
                echo 'disabled = false'
                echo 'format = "[$indicator]($style)"'
                echo 'unknown_indicator = "shell "'
                echo 'bash_indicator = "bash "'
                echo 'fish_indicator = ""'
                echo 'style = "purple bold"'
            } | tee "/mnt/root/.config/starship.toml" "/mnt/home/${ARCH_OS_USERNAME}/.config/starship.toml" >/dev/null

            # shellcheck disable=SC2028,SC2016
            { # Create fastfetch config for root & user
                echo '{'
                echo '  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",'
                echo '  "logo": {'
                echo '    "source": "arch2",'
                echo '    "type": "auto",'
                echo '    "color": {'
                echo '      "1": "magenta",'
                echo '      "2": "magenta"'
                echo '    },'
                echo '    "padding": {'
                echo '      "top": 0,'
                echo '      "left": 4,'
                echo '      "right": 8'
                echo '    }'
                echo '  },'
                echo '  "display": {'
                echo '    "key": {'
                echo '      "width": 20'
                echo '    },'
                echo '    "separator": "  →  ",'
                echo '    "color": {'
                echo '      "keys": "default",'
                echo '      "separator": "magenta"'
                echo '    }'
                echo '  },'
                echo '  "modules": ['
                echo '    "break",'
                echo '    {'
                echo '      "key": "Distro    ",'
                echo '      "type": "os",'
                echo '      "format": "Arch OS"'
                echo '    },'
                echo '    {'
                echo '      "key": "Kernel    ",'
                echo '      "type": "kernel"'
                echo '    },'
                echo '    {'
                echo '      "key": "CPU       ",'
                echo '      "type": "cpu",'
                echo '      "temp": true'
                echo '    },'
                echo '    {'
                echo '      "key": "GPU       ",'
                echo '      "type": "gpu",'
                echo '      "temp": true'
                echo '    },'
                echo '    "break",'
                echo '    {'
                echo '      "key": "Desktop   ",'
                echo '      "type": "de"'
                echo '    },'
                echo '    {'
                echo '      "key": "Manager   ",'
                echo '      "type": "wm"'
                echo '    },'
                echo '    {'
                echo '      "key": "Shell     ",'
                echo '      "type": "shell"'
                echo '    },'
                echo '    {'
                echo '      "key": "Terminal  ",'
                echo '      "type": "terminal"'
                echo '    },'
                echo '    "break",'
                echo '    {'
                echo '      "key": "Disk      ",'
                echo '      "type": "disk"'
                echo '    },'
                echo '    {'
                echo '      "key": "Memory    ",'
                echo '      "type": "memory"'
                echo '    },'
                echo '    {'
                echo '      "key": "IP        ",'
                echo '      "type": "localip"'
                echo '    },'
                echo '    {'
                echo '      "key": "Uptime    ",'
                echo '      "type": "uptime"'
                echo '    },'
                echo '    {'
                echo '      "key": "Packages  ",'
                echo '      "type": "packages"'
                echo '    },'
                echo '    "break",'
                echo '    {'
                echo '      "type": "custom",'
                echo '      "format": "{#red}●    {#green}●    {#yellow}●    {#blue}●    {#magenta}●    {#cyan}●    {#white}●    {#default}●"'
                echo '    }'
                echo '  ]'
                echo '}'
            } | tee "/mnt/root/.config/fastfetch/config.jsonc" "/mnt/home/${ARCH_OS_USERNAME}/.config/fastfetch/config.jsonc" >/dev/null

            { # Set nano environment
                echo 'EDITOR=nano'
                echo 'VISUAL=nano'
            } >/mnt/etc/environment

            # Set Nano colors
            sed -i "s/^# set linenumbers/set linenumbers/" /mnt/etc/nanorc
            sed -i "s/^# set minibar/set minibar/" /mnt/etc/nanorc
            sed -i 's;^# include "/usr/share/nano/\*\.nanorc";include "/usr/share/nano/*.nanorc"\ninclude "/usr/share/nano/extra/*.nanorc";g' /mnt/etc/nanorc

            # Set correct permissions
            arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"

            # Finished
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

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
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2016
exec_cleanup_installation() {
    local process_name="Cleanup Installation"
    process_init "$process_name"
    (
        [ "$MODE" = "debug" ] && sleep 1 && process_return 0                                                  # If debug mode then return
        arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"         # Set correct home permissions
        arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Rns --noconfirm $(pacman -Qtdq) || true' # Remove orphans and force return true
        process_return 0                                                                                      # Return
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# CHROOT HELPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

chroot_pacman_remove() { arch-chroot /mnt pacman -Rns --noconfirm "$@" || return 1; }

# ---------------------------------------------------------------------------------------------------

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
# TRAPS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

trap_gum_exit() { exit 130; }
trap_gum_exit_confirm() { gum_confirm "Exit Installation?" && trap_gum_exit; }

# ---------------------------------------------------------------------------------------------------

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

    # Cleanup
    rm -rf "$SCRIPT_TMP_DIR"

    # When ctrl + c pressed exit without other stuff below
    [ "$result_code" = "130" ] && gum_warn "Exit..." && {
        exit 1
    }

    # Check if failed and print error
    if [ "$result_code" -gt "0" ]; then
        [ -n "$error" ] && gum_fail "$error"                      # Print error message (if exists)
        [ -z "$error" ] && gum_fail "Arch OS Installation failed" # Otherwise pint default error message
        gum_warn "See ${SCRIPT_LOG} for more information..."
        gum_confirm "Show Logs?" && gum pager --show-line-numbers <"$SCRIPT_LOG" # Ask for show logs?
    fi

    exit "$result_code" # Exit installer.sh
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    [ -f "$PROCESS_RET" ] && gum_fail "${PROCESS_RET} already exists" && exit 1
    echo 1 >"$PROCESS_RET" # Init result with 1
    log_proc "${1}..."     # Log starting
}

process_capture() {
    local pid="$1"              # Set process pid
    local process_name="$2"     # Set process name
    local user_canceled="false" # Will set to true if user press ctrl + c

    # Show gum spinner until pid is not exists anymore and set user_canceled to true on failure
    gum_spin --title "${process_name}..." -- bash -c "while kill -0 $pid &> /dev/null; do sleep 1; done" || user_canceled="true"
    cat "$PROCESS_LOG" >>"$SCRIPT_LOG" # Write process log to logfile

    # When user press ctrl + c while process is running
    if [ "$user_canceled" = "true" ]; then
        kill -0 "$pid" &>/dev/null && pkill -P "$pid" &>/dev/null              # Kill process if running
        gum_fail "Process with PID ${pid} was killed by user" && trap_gum_exit # Exit with 130
    fi

    # Handle error while executing process
    [ ! -f "$PROCESS_RET" ] && gum_fail "${PROCESS_RET} not found (do not init process?)" && exit 1
    [ "$(<"$PROCESS_RET")" != "0" ] && gum_fail "${process_name} failed" && exit 1 # If process failed (result code 0 was not write in the end)

    # Finish
    rm -f "$PROCESS_RET"                            # Remove process result file
    gum_info "${process_name} sucessfully finished" # Print process success
}

process_return() {
    # 1. Write from sub process 0 to file when succeed (at the end of the script part)
    # 2. Rread from parent process after sub process finished (0=success 1=failed)
    echo "$1" >"$PROCESS_RET"
    exit "$1"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM
# ////////////////////////////////////////////////////////////////////////////////////////////////////

gum_init() {
    if [ ! -x ./gum ]; then
        clear && echo "Loading Arch OS Installer..." # Loading
        local gum_url gum_path                       # Prepare URL with version os and arch
        # https://github.com/charmbracelet/gum/releases
        gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_$(uname -s)_$(uname -m).tar.gz"
        if ! curl -Lsf "$gum_url" >"${SCRIPT_TMP_DIR}/gum.tar.gz"; then echo "Error downloading ${gum_url}" && exit 1; fi
        if ! tar -xf "${SCRIPT_TMP_DIR}/gum.tar.gz" --directory "$SCRIPT_TMP_DIR"; then echo "Error extracting ${SCRIPT_TMP_DIR}/gum.tar.gz" && exit 1; fi
        gum_path=$(find "${SCRIPT_TMP_DIR}" -type f -executable -name "gum" -print -quit)
        [ -z "$gum_path" ] && echo "Error: 'gum' binary not found in '${SCRIPT_TMP_DIR}'" && exit 1
        if ! mv "$gum_path" ./gum; then echo "Error moving ${gum_path} to ./gum" && exit 1; fi
        if ! chmod +x ./gum; then echo "Error chmod +x ./gum" && exit 1; fi
    fi
}

gum() {
    [ -n "$GUM" ] && [ ! -x "$GUM" ] && echo "Error: GUM='${GUM}' is not found or executable" >&2 && exit 1
    if [ -n "$GUM" ]; then "$GUM" "$@"; else ./gum "$@"; fi # Force open $GUM if env variable is set
}

# ---------------------------------------------------------------------------------------------------

gum_header() {
    clear && gum_purple '
 █████  ██████   ██████ ██   ██      ██████  ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
███████ ██████  ██      ███████     ██    ██ ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
██   ██ ██   ██  ██████ ██   ██      ██████  ███████'
    local header_version="${VERSION}" && [ -n "${MODE}" ] && header_version="${VERSION} (${MODE})"
    gum_white --margin "1 0" --align left --bold "Welcome to Arch OS Installer ${header_version}"
}

# ---------------------------------------------------------------------------------------------------

# Gum colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_purple() { gum_style --foreground "$COLOR_PURPLE" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }

# Gum prints
gum_title() { log_info "+ ${*}" && gum join --horizontal "$(gum_purple --bold "+ ")" "$(gum_purple --bold "${*}")"; }
gum_info() { log_info "$*" && gum join --horizontal "$(gum_green --bold "• ")" "$(gum_white --bold "${*}")"; }
gum_warn() { log_warn "$*" && gum join --horizontal "$(gum_yellow --bold "• ")" "$(gum_white --bold "${*}")"; }
gum_fail() { log_fail "$*" && gum join --horizontal "$(gum_red --bold "• ")" "$(gum_white --bold "${*}")"; }

# Gum wrapper
gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_PURPLE" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt "> " --prompt.foreground "$COLOR_PURPLE" --header.foreground "$COLOR_PURPLE" "${@}"; }
gum_write() { gum write --prompt "• " --header.foreground "$COLOR_PURPLE" --show-cursor-line --char-limit 0 "${@}"; }
gum_choose() { gum choose --cursor "> " --header.foreground "$COLOR_PURPLE" --cursor.foreground "$COLOR_PURPLE" "${@}"; }
gum_filter() { gum filter --prompt "> " --indicator ">" --placeholder "Type to filter ..." --height 8 --header.foreground "$COLOR_PURPLE" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_PURPLE" --spinner.foreground "$COLOR_PURPLE" "${@}"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOGGING
# ////////////////////////////////////////////////////////////////////////////////////////////////////

write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////////////  START MAIN  ///////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"
