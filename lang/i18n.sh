#!/usr/bin/env bash
# Internationalization loader for Arch OS installer (bash 4+)
# shellcheck disable=SC2034,SC2154

INSTALLER_LANG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -gA _I18N_EN

i18n_load() {
    local lang="${1:-en}"
    case "$lang" in
        pt | pt_BR | pt_PT) lang=pt ;;
        ru | RU) lang=ru ;;
        es | ES) lang=es ;;
        zh | zh_CN | zh_Hans | cn) lang=zh ;;
        ar | AR) lang=ar ;;
        *) lang=en ;;
    esac
    unset _I18N
    declare -gA _I18N
    # shellcheck disable=SC1091
    source "${INSTALLER_LANG_DIR}/en.sh"
    for k in "${!_I18N[@]}"; do
        _I18N_EN[$k]="${_I18N[$k]}"
    done
    if [ "$lang" != "en" ] && [ -f "${INSTALLER_LANG_DIR}/${lang}.sh" ]; then
        # shellcheck disable=SC1091
        source "${INSTALLER_LANG_DIR}/${lang}.sh"
    fi
}

# shellcheck disable=SC2059
t() {
    local k="$1" out
    out="${_I18N[$k]}"
    [ -n "$out" ] || out="${_I18N_EN[$k]}"
    [ -n "$out" ] || out="$k"
    printf '%s' "$out"
}

tf() {
    local k="$1"
    shift
    # shellcheck disable=SC2059
    printf "$(t "$k")" "$@"
}

i18n_apply_lang_from_env_or_conf() {
    : "${ARCH_OS_INSTALLER_LANG:=}"
    if [ -z "$ARCH_OS_INSTALLER_LANG" ] && [ -f "${SCRIPT_CONFIG:-./installer.conf}" ]; then
        local line
        line=$(grep -m1 '^ARCH_OS_INSTALLER_LANG=' "${SCRIPT_CONFIG}" 2>/dev/null) || true
        if [ -n "$line" ]; then
            eval "$line"
        fi
    fi
}
