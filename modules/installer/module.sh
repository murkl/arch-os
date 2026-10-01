# What several scripts of the Installer share, sourced in front of each after
# oak.sh. What one task needs stays in its folder; the functions the yaml calls
# by name are at the bottom. Why it looks the way it does: docs/REFERENCE.md

# The lookup tables beside this file.
DATA="$(dirname "${BASH_SOURCE[0]}")/data"

# The data/ folder beside the task.sh or test.sh that called it.
where() { printf '%s/data' "$(dirname "${BASH_SOURCE[1]}")"; }

# ////////////////////////////////////////////////////////////////////////////
# FILES A TASK SHIPS
# ////////////////////////////////////////////////////////////////////////////

# A template from a task's data/ on stdout: {{NAME}} filled from NAME=value,
# every $ left for whoever reads the file later. A placeholder nobody filled and
# a value nothing asks for both fail. Why not envsubst: docs/REFERENCE.md
render() {
    local template="$1" open='{{' close='}}' text rendered="" name pair
    local -A values=() used=()
    shift

    [ -f "$template" ] || {
        echo "there is no template ${template}" >&2
        return 1
    }

    for pair in "$@"; do
        name="${pair%%=*}"
        [[ $pair == *=* && $name =~ ^[A-Z][A-Z0-9_]*$ ]] || {
            echo "${pair} is not a NAME=value for ${template}" >&2
            return 1
        }
        values["$name"]="${pair#*=}"
    done

    # Whole, trailing newlines included, which $(<file) would strip.
    IFS= read -r -d '' text <"$template" || true

    # Left to right and once, so a value that happens to hold {{ is never read
    # as a placeholder of its own.
    while [[ $text == *"$open"* ]]; do
        rendered+="${text%%"$open"*}"
        text="${text#*"$open"}"
        name="${text%%"$close"*}"
        if [[ $text != *"$close"* || ! $name =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            echo "${template} has a ${open} that opens no placeholder" >&2
            return 1
        fi
        if [[ ! -v values[$name] ]]; then
            echo "${template} asks for ${open}${name}${close}, which nobody handed over" >&2
            return 1
        fi
        rendered+="${values[$name]}"
        used["$name"]=1
        text="${text#*"$close"}"
    done

    for name in "${!values[@]}"; do
        [[ -v used[$name] ]] || {
            echo "${name} was handed to ${template}, which never asks for it" >&2
            return 1
        }
    done

    printf '%s' "${rendered}${text}"
}

# ////////////////////////////////////////////////////////////////////////////
# LOCALE LOOKUP
# ////////////////////////////////////////////////////////////////////////////

# Keyboard, font and time zone do not follow from the shape of a locale - de_CH
# is not de - so they are looked up in data/.

# A column of data/languages for a locale: its own row, else its language's.
language_field() {
    awk -v col="$1" -v locale="${2%%.*}" '
        BEGIN { lang = locale; sub(/_.*/, "", lang) }
        /^#/ || NF == 0 { next }
        $1 == locale { hit = $0; exit }
        $1 == lang && fallback == "" { fallback = $0 }
        END { split(hit != "" ? hit : fallback, f); print f[col] }
    ' "${DATA}/languages"
}

# A column of data/countries for a territory code; empty for none.
country_field() {
    awk -F'\t' -v col="$1" -v code="$2" 'code != "" && $1 == code { print $col }' "${DATA}/countries"
}

# auto: not answered yet, work it out. none: answered, empty.
is_auto() { [ -z "$1" ] || [ "$1" = "auto" ]; }
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# What each list resolves to on auto - functions, because the page shows the
# same answer beside its auto row.
auto_keymap() {
    local keymap
    keymap="$(language_field 2 "$ARCH_OS_LOCALE_LANG")"
    # Otherwise the keyboard the live image was started with.
    printf '%s' "${keymap:-$(live_keymap)}"
}

auto_layout() {
    local layout
    layout="$(language_field 3 "$ARCH_OS_LOCALE_LANG")"
    if [ -z "$layout" ]; then
        layout="$(auto_keymap)"
        layout="${layout%%-*}"
    fi
    printf '%s' "$layout"
}

# none rather than empty: the console keeps its font, every mirror is ranked.
auto_font() {
    local font
    font="$(language_field 4 "$ARCH_OS_LOCALE_LANG")"
    printf '%s' "${font:-none}"
}

# The country of the time zone rather than the language: en_US is typed on
# every continent, and a mirror an ocean away cannot be rated in time.
auto_country() {
    local territory country
    territory="$(awk -F'\t' -v zone="$ARCH_OS_TIMEZONE" \
        '!/^#/ && zone != "" && $3 == zone { print $1 }' /usr/share/zoneinfo/zone.tab)"
    country="$(country_field 2 "$territory")"
    [ "$country" = "-" ] && country="" # a country Arch has no mirror in
    printf '%s' "${country:-none}"
}

# ////////////////////////////////////////////////////////////////////////////
# THE ANSWERS, RESOLVED
# ////////////////////////////////////////////////////////////////////////////

# The partitions the disk is laid out into; the third only with the Recovery.
# Read by the tasks, which shellcheck reads one at a time.
# shellcheck disable=SC2034
BOOT_PART="$(part_of "$ARCH_OS_DISK" 1)"
# shellcheck disable=SC2034
ROOT_PART="$(part_of "$ARCH_OS_DISK" 2)"
# shellcheck disable=SC2034
RECOVERY_PART="$(part_of "$ARCH_OS_DISK" 3)"

is_auto "$ARCH_OS_VCONSOLE_KEYMAP" && ARCH_OS_VCONSOLE_KEYMAP="$(auto_keymap)"
is_auto "$ARCH_OS_VCONSOLE_FONT" && ARCH_OS_VCONSOLE_FONT="$(auto_font)"
is_auto "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" && ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="$(auto_layout)"
is_auto "$ARCH_OS_REFLECTOR_COUNTRY" && ARCH_OS_REFLECTOR_COUNTRY="$(auto_country)"

ARCH_OS_VCONSOLE_FONT="$(not_none "$ARCH_OS_VCONSOLE_FONT")"
ARCH_OS_REFLECTOR_COUNTRY="$(not_none "$ARCH_OS_REFLECTOR_COUNTRY")"
ARCH_OS_DESKTOP_KEYBOARD_VARIANT="$(not_none "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT")"

# ////////////////////////////////////////////////////////////////////////////
# THE MACHINE
# ////////////////////////////////////////////////////////////////////////////

# The processor's microcode package, or nothing.
microcode() {
    if grep -q GenuineIntel /proc/cpuinfo; then
        echo intel-ucode
    elif grep -q AuthenticAMD /proc/cpuinfo; then
        echo amd-ucode
    fi
}

# Each graphics card: the vendor as the driver packages name it, a tab, the PCI
# device ID - off sysfs rather than lspci's table. A virtual machine's own
# adapter is none of the three and is left out.
graphics_cards() {
    local dev vendor
    for dev in /sys/bus/pci/devices/*; do
        [[ $(<"${dev}/class") == 0x03* ]] || continue
        case "$(<"${dev}/vendor")" in
        0x8086) vendor=intel ;;
        0x1002) vendor=amd ;;
        0x10de) vendor=nvidia ;;
        *) continue ;;
        esac
        printf '%s\t%s\n' "$vendor" "$(<"${dev}/device")"
    done
}

# ////////////////////////////////////////////////////////////////////////////
# THE BOOT CHAIN
# ////////////////////////////////////////////////////////////////////////////

# Secure Boot always means a unified kernel image.
# https://wiki.archlinux.org/title/Unified_kernel_image
secure_boot_wanted() {
    [ "$ARCH_OS_SECURE_BOOT_ENABLED" = "true" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]
}

# The images the firmware starts - a check against the other two checks nothing.
boot_images() {
    if secure_boot_wanted; then
        printf '/boot/EFI/Linux/arch-%s.efi\n/boot/EFI/Linux/arch-%s-fallback.efi\n' "$KERNEL" "$KERNEL"
    else
        printf '/boot/initramfs-%s.img\n/boot/initramfs-%s-fallback.img\n' "$KERNEL" "$KERNEL"
    fi
}

# The Recovery image: on the Arch OS ISO already, else fetched into /tmp, which
# holds more than the image's writable layer. How it boots: docs/REFERENCE.md
RECOVERY_IMAGE=/opt/arch-os-recovery
[ -d "$RECOVERY_IMAGE" ] || RECOVERY_IMAGE=/tmp/arch-os-recovery

# Where it lands on the EFI partition, listed by systemd-boot on its own.
# shellcheck disable=SC2034
RECOVERY_EFI=/boot/EFI/Linux/arch-os-recovery.efi

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING INTO THE NEW SYSTEM
# ////////////////////////////////////////////////////////////////////////////

# Retried: the network is what reliably goes wrong. pacman's own timeout stays,
# which turns a mirror gone away into a retry against the next.
RETRIES=5
RETRY_WAIT=10

chroot_pacman_install() {
    local i
    for ((i = 1; i <= RETRIES; i++)); do
        [ "$i" -gt 1 ] && echo "retry ${i}/${RETRIES}: pacman -S $*"
        if arch-chroot "$MNT" pacman -S --noconfirm --needed "$@"; then
            return 0
        fi
        sleep "$RETRY_WAIT"
    done
    echo "pacman failed after ${RETRIES} attempts: $*" >&2
    return 1
}

# A sudo rule from stdin as a drop-in, taken back out where visudo refuses it:
# one unreadable file there refuses every sudo. https://wiki.archlinux.org/title/Sudo
sudoers_rule() {
    local file="${MNT}/etc/sudoers.d/${1}"
    mkdir -p "${MNT}/etc/sudoers.d"
    cat >"$file"
    chmod 0440 "$file"

    # A rule sudo will not parse is taken back out rather than left lying
    # there: one unreadable file in that directory is enough to refuse every
    # sudo on the machine, and a rule that failed is better gone than kept.
    arch-chroot "$MNT" visudo -cqf "/etc/sudoers.d/${1}" && return 0
    rm -f "$file"
    echo "the sudo rule ${1} was rejected and was removed again" >&2
    return 1
}

# pacman reads no drop-in directory but follows an Include, so each setting is a
# file under /etc/pacman.d named by one line - the one edit a .pacnew carries.
# Named outright: a glob matching nothing stops pacman.
# https://man.archlinux.org/man/pacman.conf.5
pacman_include() {
    local file
    file="/etc/pacman.d/$(basename "$1")"
    render "$1" >"${MNT}${file}"
    grep -qxF "Include = ${file}" "${MNT}/etc/pacman.conf" ||
        echo "Include = ${file}" >>"${MNT}/etc/pacman.conf"
}

# One attempt's time limit, and how often a build is tried: downloads fail, a
# build that hits the limit was stuck.
AUR_RETRIES=3
AUR_TIMEOUT=2700

# A package from the AUR, built as the account with passwordless sudo granted
# for the build alone. One compile job per GiB of memory - see docs/REFERENCE.md.
chroot_aur_install() {
    local repo="$1"
    local url="https://aur.archlinux.org/${repo}.git"
    local dir jobs cores build status=1 i

    chroot_pacman_install git base-devel

    jobs=$(($(awk '/^MemTotal:/ { print $2 }' /proc/meminfo) / 1048576))
    cores="$(nproc)"
    [ "$jobs" -lt 1 ] && jobs=1
    [ "$jobs" -gt "$cores" ] && jobs="$cores"

    dir="$(mktemp -u "/home/${ARCH_OS_USERNAME}/.aur-${repo}.XXXX")"
    build="rm -rf ${dir} && git clone --depth 1 ${url} ${dir} && cd ${dir}"
    # Added to the options the PKGBUILD sets rather than put in their place: one
    # that says !lto would otherwise be built with what its author ruled out.
    build="${build} && printf '\noptions+=(\"!debug\")\n' >>PKGBUILD"
    # make and cargo are named separately because neither reads the other. The
    # caches cargo fills are kept inside the build directory, so they go with
    # it: otherwise paru's crate registry, well over a hundred megabytes, stays
    # in the new home for good.
    build="${build} && MAKEFLAGS=-j${jobs} CARGO_BUILD_JOBS=${jobs}"
    build="${build} CARGO_HOME=${dir}/.cargo XDG_CACHE_HOME=${dir}/.cache"
    build="${build} makepkg -si --noconfirm --needed"

    echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | sudoers_rule 99-aur-build

    echo "building ${repo} from the AUR with ${jobs} job(s)"
    for ((i = 1; i <= AUR_RETRIES; i++)); do
        [ "$i" -gt 1 ] && echo "retry ${i}/${AUR_RETRIES}: building ${repo} from the AUR"
        status=0
        arch-chroot "$MNT" timeout "$AUR_TIMEOUT" \
            /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "$build" || status=$?
        [ "$status" -eq 0 ] && break
        if [ "$status" -eq 124 ]; then
            echo "building ${repo} from the AUR was still running after $((AUR_TIMEOUT / 60)) minutes and was stopped" >&2
            break
        fi
        sleep "$RETRY_WAIT"
    done

    # Taken back first, before anything that can fail: a cleanup that dies on
    # a root-owned file the build left behind would otherwise leave passwordless
    # sudo standing in the installed system.
    rm -f "${MNT}/etc/sudoers.d/99-aur-build"
    rm -rf "${MNT}${dir}" || echo "the build directory ${dir} could not be removed" >&2

    [ "$status" -eq 0 ] || echo "building ${repo} from the AUR did not finish" >&2
    return "$status"
}

# A command inside the new system as the account, which makepkg insists on.
as_user() {
    arch-chroot "$MNT" /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "$1"
}

# The chosen browser's desktop entry - not its package's name for two of them.
browser_entry() {
    case "$ARCH_OS_BROWSER" in
    epiphany) echo org.gnome.Epiphany.desktop ;;
    vivaldi) echo vivaldi-stable.desktop ;;
    *) echo "${ARCH_OS_BROWSER}.desktop" ;;
    esac
}

# The new home given back to its account: what root wrote is root's until then.
own_home() {
    arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
}

# Asked of the new system: a link in its /usr/bin may be absolute, which out
# here points into the live system. Arch puts every binary in /usr/bin.
has_command() { arch-chroot "$MNT" test -x "/usr/bin/${1}"; }

# sysctl says nothing about a key it does not have, so each is looked for.
sysctl_keys_exist() {
    local keys key
    keys="$(sed -n 's/^[[:space:]]*\([a-z][a-z0-9._-]*\)[[:space:]]*=.*/\1/p' "$1")"

    # No keys at all would be a loop over nothing, which is a check that passes
    # without having looked - the failure this exists to catch, arriving as a pass.
    [ -n "$keys" ] || {
        echo "${1} sets nothing at all" >&2
        return 1
    }

    while read -r key; do
        [ -e "/proc/sys/${key//.//}" ] || {
            echo "${1} sets ${key}, which this kernel does not have" >&2
            return 1
        }
    done <<<"$keys"
}

# ////////////////////////////////////////////////////////////////////////////
# FIRST LOGIN
# ////////////////////////////////////////////////////////////////////////////

# Settings only a session can take: tasks append lines here, and the
# first-login task turns them into a script that runs once.
HOME_DIR="${MNT}/home/${ARCH_OS_USERNAME}"
FIRST_LOGIN="${HOME_DIR}/.first-login"

on_first_login() { cat >>"$FIRST_LOGIN"; }

# ////////////////////////////////////////////////////////////////////////////
# THE YAML | Every function a declaration calls by name
# ////////////////////////////////////////////////////////////////////////////

in_virtual_machine() {
    if systemd-detect-virt -q; then echo true; else echo false; fi
}

# Loaded the moment it is answered, so what is typed next is typed on it.
load_console_keyboard() {
    debugging && return 0
    loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
}

# A list may print a value and the text it is chosen by, with a tab between.

# Every locale glibc ships that locale.gen knows; @-variants double the list.
list_locales() {
    comm -12 \
        <(basename -a /usr/share/i18n/locales/* | grep -v '@' | sort -u) \
        <(sed -n 's/^#\? *\([a-zA-Z_]*\)[. ].*/\1/p' /etc/locale.gen | sort -u)
}

# Not Afar, the first row: the one locale this installer generates either way.
default_locale() { printf 'en_US'; }

list_keymaps() {
    printf 'auto\tauto — %s\n' "$(auto_keymap)"
    localectl list-keymaps
}

list_fonts() {
    printf 'auto\tauto — %s\n' "$(auto_font)"
    echo none
    find /usr/share/kbd/consolefonts -name '*.psf*' -printf '%f\n' 2>/dev/null |
        sed 's/\.psfu\?\(\.gz\)\?$//' | sort -u
}

list_timezones() { timedatectl list-timezones; }

# The zone of the chosen country, and UTC rather than Africa/Abidjan for none.
auto_timezone() {
    local locale="${ARCH_OS_LOCALE_LANG%%.*}" territory="" zone
    [[ $locale == *_* ]] && territory="${locale#*_}"
    zone="$(country_field 3 "$territory")"
    printf '%s' "${zone:-UTC}"
}

list_countries() {
    printf 'auto\tauto — %s\n' "$(auto_country)"
    echo none
    # A "-" marks a country Arch has no mirror in.
    awk -F'\t' '!/^#/ && $2 != "-" { print $2 }' "${DATA}/countries"
}

# Asked of the running system where it can answer; the Arch ISO ships no
# xkeyboard-config, and then data/ answers.
list_layouts() {
    printf 'auto\tauto — %s\n' "$(auto_layout)"

    local layouts
    layouts="$(localectl list-x11-keymap-layouts 2>/dev/null || true)"
    if [ -n "$layouts" ]; then
        echo "$layouts"
        return 0
    fi
    grep -v '^#' "${DATA}/x11-layouts"
}

list_variants() {
    local layout="$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" variants
    [ -n "$layout" ] || return 0

    echo none

    variants="$(localectl list-x11-keymap-variants "$layout" 2>/dev/null || true)"
    if [ -n "$variants" ]; then
        echo "$variants"
        return 0
    fi
    # A layout without variants has no line there, which is not a failure.
    { grep "^${layout} " "${DATA}/x11-variants" || true; } | cut -d' ' -f2- | tr ' ' '\n'
}
