# What more than one script of this module has to agree about, sourced by Oak in
# front of every one of them. Anything a single script needs stays in that
# script; the functions a declaration calls by name are at the bottom.
#
# Why it looks the way it does: docs/REFERENCE.md

# Where the new system is mounted while it is being built, and the lookup tables
# next to this file.
MNT=/mnt
DATA="$(dirname "${BASH_SOURCE[0]}")/data"

# Where the task that called it keeps the files it ships with: data/ beside its
# task.sh, so the folder a task is and the files it writes are told apart at a
# glance.
where() { printf '%s/data' "$(dirname "${BASH_SOURCE[1]}")"; }

# ////////////////////////////////////////////////////////////////////////////
# FILES A TASK SHIPS
# ////////////////////////////////////////////////////////////////////////////

# Every file a task writes into the new system lies beside it and comes out
# through here, on stdout. {{NAME}} is replaced by what was handed over as
# NAME=value; everything else is left as it stands, so ${HOME}, $trg or $(date)
# reach the shell, systemd or pacman that reads the file later untouched.
#
# Both sides are checked: a placeholder nobody filled and a value nothing asks
# for are each a failure, because either writes a file that reads perfectly well
# and does not say what it was meant to. Why not envsubst: docs/REFERENCE.md
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

# Keyboard, font and timezone do not follow from the shape of a locale - de_CH
# is not de, sv is not se - so all three are looked up in data/. The mirror
# country is looked up there too, but follows the time zone rather than the
# language: see auto_country.

# A column of the data/languages row for a locale: its own row if there is one,
# otherwise its language's row.
language_field() {
    awk -v col="$1" -v locale="${2%%.*}" '
        BEGIN { lang = locale; sub(/_.*/, "", lang) }
        /^#/ || NF == 0 { next }
        $1 == locale { hit = $0; exit }
        $1 == lang && fallback == "" { fallback = $0 }
        END { split(hit != "" ? hit : fallback, f); print f[col] }
    ' "${DATA}/languages"
}

# A column of the data/countries row for a territory code: the two capitals a
# locale ends in, and the ones tzdata files a zone under. Empty for a code it has
# no row for, and for no code at all.
country_field() {
    awk -F'\t' -v col="$1" -v code="$2" 'code != "" && $1 == code { print $col }' "${DATA}/countries"
}

# The two magic words the lists share; neither ever reaches a task. auto means
# "not answered yet, work it out"; none means "answered: empty".
is_auto() { [ -z "$1" ] || [ "$1" = "auto" ]; }
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# What each list resolves to on auto. Functions rather than inlined, because the
# question page shows the same answer next to its auto row.
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

# Both fall back to none rather than to empty: no font means the console keeps
# its own, no country means every mirror ranked by speed.
auto_font() {
    local font
    font="$(language_field 4 "$ARCH_OS_LOCALE_LANG")"
    printf '%s' "${font:-none}"
}

# The country the chosen time zone lies in, as tzdata files it, rather than the
# one the language names: en_US is typed on every continent, and a mirror an
# ocean away is not only slow but cannot even be rated within reflector's own
# timeout.
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

# The two partitions the disk is laid out into, named once here so every task
# means the same devices. Only the tasks use the first, and shellcheck reads
# this file without them.
# shellcheck disable=SC2034
BOOT_PART="$(part_of "$ARCH_OS_DISK" 1)"
ROOT_PART="$(part_of "$ARCH_OS_DISK" 2)"

is_auto "$ARCH_OS_VCONSOLE_KEYMAP" && ARCH_OS_VCONSOLE_KEYMAP="$(auto_keymap)"
is_auto "$ARCH_OS_VCONSOLE_FONT" && ARCH_OS_VCONSOLE_FONT="$(auto_font)"
is_auto "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" && ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="$(auto_layout)"
is_auto "$ARCH_OS_REFLECTOR_COUNTRY" && ARCH_OS_REFLECTOR_COUNTRY="$(auto_country)"

ARCH_OS_VCONSOLE_FONT="$(not_none "$ARCH_OS_VCONSOLE_FONT")"
ARCH_OS_REFLECTOR_COUNTRY="$(not_none "$ARCH_OS_REFLECTOR_COUNTRY")"
ARCH_OS_DESKTOP_KEYBOARD_VARIANT="$(not_none "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT")"

# The console keyboard and font of the new system. A function rather than four
# lines in configure-system, because it is needed before that runs: mkinitcpio's
# sd-vconsole hook reads this file while pacstrap builds the ram disk.
write_vconsole() {
    mkdir -p "${MNT}/etc"
    echo "KEYMAP=${ARCH_OS_VCONSOLE_KEYMAP}" >"${MNT}/etc/vconsole.conf"
    [ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=${ARCH_OS_VCONSOLE_FONT}" >>"${MNT}/etc/vconsole.conf"
    return 0
}

# ////////////////////////////////////////////////////////////////////////////
# THE MACHINE
# ////////////////////////////////////////////////////////////////////////////

# The one kernel Arch OS installs.
KERNEL=linux-zen

# The processor's microcode package, or nothing for a processor neither vendor
# ships one for.
microcode() {
    if grep -q GenuineIntel /proc/cpuinfo; then
        echo intel-ucode
    elif grep -q AuthenticAMD /proc/cpuinfo; then
        echo amd-ucode
    fi
}

# The graphics cards in this machine, one line each: the vendor as the driver
# packages name it, a tab, and the PCI device ID. Read off sysfs, where lspci
# reads them too, rather than out of the table lspci draws for a person. A
# virtual machine's own display adapter belongs to none of the three and is left
# out, so a guest lists a card only where a real one was passed through to it.
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
# SNAPPER
# ////////////////////////////////////////////////////////////////////////////

# What snapper's own defaults have to become here, one setting per line. Its
# defaults are written for a system that changes slowly and a rolling release
# is not one - why these numbers, and why no timeline: docs/REFERENCE.md. The
# last two are what makes the group /.snapshots belongs to able to read it:
# without them snapper answers nobody but root, whatever the directory says.
#
# Named once because the task sets them and its test reads them back, and
# because set-config takes one KEY=VALUE per argument - handed the four as one
# string it writes the whole line into the first key, sets nothing else, and
# says nothing about it.
snapper_config() {
    printf '%s\n' \
        NUMBER_LIMIT=10 \
        NUMBER_LIMIT_IMPORTANT=5 \
        TIMELINE_CREATE=no \
        ALLOW_GROUPS=wheel \
        SYNC_ACL=yes
}

# ////////////////////////////////////////////////////////////////////////////
# SECURE BOOT & KERNEL COMMAND LINE
# ////////////////////////////////////////////////////////////////////////////

# Whether this installation gets Secure Boot, which always means a unified
# kernel image. The boot loader and the ram disk are both built differently for
# a signed boot chain, so the rule is named once instead of repeated.
# https://wiki.archlinux.org/title/Unified_kernel_image
secure_boot_wanted() {
    [ "$ARCH_OS_SECURE_BOOT_ENABLED" = "true" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]
}

# The images the firmware actually starts. Named once because the initramfs task
# writes them, the boot splash rebuilds them and two tests read them back - and
# a check against the image this machine does not start from checks nothing.
boot_images() {
    if secure_boot_wanted; then
        printf '/boot/EFI/Linux/arch-%s.efi\n/boot/EFI/Linux/arch-%s-fallback.efi\n' "$KERNEL" "$KERNEL"
    else
        printf '/boot/initramfs-%s.img\n/boot/initramfs-%s-fallback.img\n' "$KERNEL" "$KERNEL"
    fi
}

# The kernel command line, read by the unified kernel image and by systemd-boot's
# entries - one answer, so no two of them can disagree about how this system
# boots. Why each parameter is here: docs/REFERENCE.md
kernel_args() {
    local args=(rw)

    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        args+=(root=/dev/mapper/cryptroot "rd.luks.name=$(blkid -s UUID -o value "$ROOT_PART")=cryptroot")
    else
        args+=("root=PARTUUID=$(lsblk -dno PARTUUID "$ROOT_PART")")
    fi

    args+=(rootflags=subvol=@ rootfstype=btrfs)
    args+=(zswap.enabled=0) # pointless next to zram, and the two interfere

    [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ] && args+=(nowatchdog)

    # https://wiki.archlinux.org/title/Silent_boot
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ]; then
        args+=(quiet splash vt.global_cursor_default=0 loglevel=3 rd.udev.log_level=3 systemd.show_status=auto)
    fi

    # Plymouth forces its text plugin the moment it finds a serial console and
    # never looks for a screen again: no splash, and the passphrase asked in
    # plain type. A virtual machine is handed one without asking.
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then
        args+=(plymouth.ignore-serial-consoles)
    fi

    [ -n "$ARCH_OS_KERNEL_ARGS" ] && args+=("$ARCH_OS_KERNEL_ARGS")
    printf '%s' "${args[*]}"
}

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING INTO THE NEW SYSTEM
# ////////////////////////////////////////////////////////////////////////////

# Package installs are retried: the one thing that reliably goes wrong during an
# installation is the network. pacman's own download timeout is left on, which
# is what turns a mirror that went away into a retry against the next one.
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

# A sudo rule in the new system, read from stdin, as a drop-in and checked
# before it is trusted: a syntax error in /etc/sudoers locks everybody out of
# root. https://wiki.archlinux.org/title/Sudo
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

# pacman reads no drop-in directory, but it follows an Include from any section
# of its one file. So each setting made here is a file of its own under
# /etc/pacman.d, and pacman.conf gains one line naming it - the one edit a
# .pacnew then asks to carry over. Named outright rather than by a glob, because
# a glob that matches nothing stops pacman altogether.
# https://man.archlinux.org/man/pacman.conf.5
pacman_include() {
    local file
    file="/etc/pacman.d/$(basename "$1")"
    render "$1" >"${MNT}${file}"
    grep -qxF "Include = ${file}" "${MNT}/etc/pacman.conf" ||
        echo "Include = ${file}" >>"${MNT}/etc/pacman.conf"
}

# How long one attempt at an AUR build may take and how often it is tried. A
# build is retried because what fails in one is downloads; a build that runs
# into the limit is not, because it was stuck rather than failing.
AUR_RETRIES=3
AUR_TIMEOUT=2700

# Building from the AUR needs a normal user allowed to sudo without a password,
# granted for the length of the build and taken back afterwards. The build tools
# are installed here rather than by each of the three tasks that build.
#
# One command inside the target so that one timeout covers the whole build, and
# one compile job per gigabyte of memory - see docs/REFERENCE.md for why a live
# image that takes its cores at their word runs itself out of memory.
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

# A command inside the new system as the account being created - what makepkg
# insists on, and what anything writing into that home should do anyway.
as_user() {
    arch-chroot "$MNT" /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "$1"
}

# The new home given back to the account it belongs to. Everything written from
# out here belongs to root until this has run, and a home the user cannot write
# to is a desktop that comes up broken.
own_home() {
    arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
}

# Whether the new system has a command. Read off the mounted tree rather than
# looked up inside it: `command -v` is a shell builtin and arch-chroot execs a
# binary. Arch puts every binary in /usr/bin.
has_command() { [ -x "${MNT}/usr/bin/${1}" ]; }

# Whether every setting in a sysctl drop-in names a knob that exists. sysctl
# makes no complaint about a key it has never heard of, so a misspelled or
# long-renamed one is a line that does nothing on a file that looks right.
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

# Some desktop settings only live in the user's own database, and there is no
# session yet to write them into. Tasks append lines here; the first-login task
# turns them into a script that runs once and then removes itself.
#
# Where the three pieces land follows the XDG base directory specification,
# which also keeps them clear of ~/.arch-os - that folder belongs to the manager.
# https://specifications.freedesktop.org/basedir-spec/latest/
HOME_DIR="${MNT}/home/${ARCH_OS_USERNAME}"

# Only while the run is on; the first-login task turns it into the three below.
FIRST_LOGIN="${HOME_DIR}/.first-login"

# Shellcheck reads this file on its own and cannot see that Oak sources it in
# front of every task, so each of the three looks unused here.
# shellcheck disable=SC2034
FIRST_LOGIN_SCRIPT="${HOME_DIR}/.local/share/arch-os/first-login.sh"
# Relative, because the account itself writes it, from its own home.
# shellcheck disable=SC2034
FIRST_LOGIN_LOG=".local/state/arch-os/first-login.log"
# shellcheck disable=SC2034
FIRST_LOGIN_ENTRY="${HOME_DIR}/.config/autostart/arch-os-first-login.desktop"

on_first_login() { cat >>"$FIRST_LOGIN"; }

# ////////////////////////////////////////////////////////////////////////////
# CLOSING THE TARGET
# ////////////////////////////////////////////////////////////////////////////

# The target closed for good: swap off, everything unmounted and the encrypted
# volume locked again - named once so the init task, the unmount task, the
# restart and the shutdown cannot disagree about what closing is.
#
# Nothing mounted is not an error: this runs before the first partition is made
# as well as after the last file is written. Whatever still holds the target is
# named in the log and then killed, and the second umount is left unguarded on
# purpose - that one is a real failure.
#
# -R and not -A, and -M on both fuser lines: see docs/REFERENCE.md.
close_target() {
    swapoff -a || true
    sync

    if mountpoint -q "$MNT" && ! umount -R "$MNT"; then
        echo "the target did not unmount, what is holding it:"
        fuser -Mvm "$MNT" || true
        fuser -Mkm "$MNT" || true
        sleep 2 # the kernel needs a moment to actually let go of the files
        umount -R "$MNT"
    fi

    [ -e /dev/mapper/cryptroot ] && cryptsetup close cryptroot
    echo "closed ${MNT}"
}

# ////////////////////////////////////////////////////////////////////////////
# THE YAML | Every function a declaration calls by name
# ////////////////////////////////////////////////////////////////////////////

# A page of awk inside a yaml scalar is read by nobody and checked by nothing,
# so every list a question offers, every value one opens on and every check a
# declaration makes is a function here.

# Real HTTPS to a host the installation needs anyway, not a ping - a captive
# portal answers pings too.
is_online() {
    fetch_url -s --connect-timeout 5 --max-time 15 https://archlinux.org >/dev/null
}

# Whether this machine is itself a virtual one: the guest tools go in without a
# question there, and running virtual machines of its own is asked only where
# it is not.
in_virtual_machine() {
    if systemd-detect-virt -q; then echo true; else echo false; fi
}

# The keyboard on the machine the installer runs on, loaded the moment the
# language or the keyboard is answered: until then, everything typed after it is
# typed on a layout nobody chose. A simulated run is on somebody's own machine.
load_console_keyboard() {
    debugging && return 0
    loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
}

# A list may hand back a value and the text it is chosen by on one line,
# separated by a tab: everything before the tab is stored, everything after it
# is read. That is how an auto row says what auto currently comes to.

# Every locale the C library ships that /etc/locale.gen also knows about: one
# that cannot be generated cannot be used. The @-suffixed variants are the same
# language in another script or currency, and double a long list.
list_locales() {
    comm -12 \
        <(basename -a /usr/share/i18n/locales/* | grep -v '@' | sort -u) \
        <(sed -n 's/^#\? *\([a-zA-Z_]*\)[. ].*/\1/p' /etc/locale.gen | sort -u)
}

# The row that list opens on, which on a list sorted by name would otherwise be
# Afar as spoken in Djibouti - an answer nobody means and the one an enter meant
# for the page before gives. Nothing on this machine says better: the console
# keyboard answered a page earlier names a language and not a country, and a
# keymap like `es` is four of them; asking a geolocation service where the
# machine stands is not a call an installer makes unasked. So it opens on the
# one locale this installer generates either way, and the list is filtered from
# there.
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

# The timezone the chosen country keeps, and UTC where the locale names no
# country. Only ever the value the list opens on.
#
# UTC rather than nothing: an empty suggestion opens the list on its own first
# row, which is Africa/Abidjan, and an enter meant for the page before sets the
# clock to it.
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

# The desktop keyboard is asked of the running system where it can answer and
# read from data/ where it cannot: the official Arch live image ships no
# xkeyboard-config, and localectl then fails rather than printing nothing.
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

# The layout is already resolved by the time this is asked - auto became a real
# one before it ran.
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
