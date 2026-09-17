# What more than one script of this module has to agree about, sourced by Oak in
# front of every one of them. Anything a single script needs stays in that
# script; the functions a declaration calls by name are at the bottom.
#
# Why it looks the way it does: docs/REFERENCE.md

# Where the new system is mounted while it is being built, and the lookup tables
# next to this file.
MNT=/mnt
DATA="$(dirname "${BASH_SOURCE[0]}")/data"

# The folder of the task that called it, where a unit keeps the files it ships
# with.
where() { dirname "${BASH_SOURCE[1]}"; }

# ////////////////////////////////////////////////////////////////////////////
# SIMULATION
# ////////////////////////////////////////////////////////////////////////////

# --debug runs without touching the machine: a task opens with `simulating &&
# return 0`, a test with `debugging && return 0`. The pause is the difference —
# it holds a step on screen, and a test is not a step anybody is watching.

debugging() { [ "$DEBUG" = "true" ]; }

simulating() {
    debugging || return 1
    echo "simulated"
    sleep 1
}

# ////////////////////////////////////////////////////////////////////////////
# LOCALE LOOKUP
# ////////////////////////////////////////////////////////////////////////////

# Keyboard, font, mirror country and timezone do not follow from the shape of a
# locale - de_CH is not de, sv is not se - so all four are looked up in data/.

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

# A column of the data/countries row for the territory a locale ends in. Empty
# for a locale that names none.
country_field() {
    local locale="${2%%.*}"
    [ "${locale#*_}" != "$locale" ] || return 0
    awk -F'\t' -v col="$1" -v code="${locale#*_}" '$1 == code { print $col }' "${DATA}/countries"
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
    # Otherwise the keyboard the live image was started with, which the Arch
    # image records only as the loadkeys command in root's shell history.
    # Finding nothing there is the ordinary case, so the grep must not make a
    # failure of it - pipefail would carry that out of the whole lookup.
    : "${keymap:=$({ grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ')}"
    printf '%s' "${keymap:-us}"
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

auto_country() {
    local country
    country="$(country_field 2 "$ARCH_OS_LOCALE_LANG")"
    [ "$country" = "-" ] && country="" # a country Arch has no mirror in
    printf '%s' "${country:-none}"
}

auto_microcode() {
    if grep -q GenuineIntel /proc/cpuinfo; then
        echo intel-ucode
    elif grep -q AuthenticAMD /proc/cpuinfo; then
        echo amd-ucode
    else
        echo none
    fi
}

# ////////////////////////////////////////////////////////////////////////////
# THE ANSWERS, RESOLVED
# ////////////////////////////////////////////////////////////////////////////

# Names a partition of a disk. Devices whose name ends in a digit (nvme0n1,
# mmcblk0, loop0) get a p between the disk and the partition number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

# Resolved once here instead of in a task, so every task sees the same answer
# regardless of how it was arrived at.
: "${ARCH_OS_BOOT_PARTITION:=$(part_of "$ARCH_OS_DISK" 1)}"
: "${ARCH_OS_ROOT_PARTITION:=$(part_of "$ARCH_OS_DISK" 2)}"

is_auto "$ARCH_OS_VCONSOLE_KEYMAP" && ARCH_OS_VCONSOLE_KEYMAP="$(auto_keymap)"
is_auto "$ARCH_OS_VCONSOLE_FONT" && ARCH_OS_VCONSOLE_FONT="$(auto_font)"
is_auto "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" && ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="$(auto_layout)"
is_auto "$ARCH_OS_REFLECTOR_COUNTRY" && ARCH_OS_REFLECTOR_COUNTRY="$(auto_country)"
is_auto "$ARCH_OS_MICROCODE" && ARCH_OS_MICROCODE="$(auto_microcode)"

# Autologin follows disk encryption: a disk already unlocked by a password at
# boot gains nothing from a second one at the login screen.
is_auto "$ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED" && ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED="${ARCH_OS_ENCRYPTION_ENABLED:-false}"

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
# THE BTRFS LAYOUT
# ////////////////////////////////////////////////////////////////////////////

# How this project mounts btrfs, and what it lays down: subvolume, a tab, then
# where it belongs. The recovery carries the same table and mounts whichever of
# them an installation actually has - the two must not drift apart.
#
# Why the three under /var are separate: docs/REFERENCE.md
#
# Shellcheck reads this file on its own and cannot see that Oak sources it in
# front of every task, so the option string looks unused here.
# shellcheck disable=SC2034
BTRFS_OPTS="defaults,noatime,compress=zstd"

btrfs_subvolumes() {
    printf '%s\t%s\n' \
        @ / \
        @home /home \
        @snapshots /.snapshots \
        @log /var/log \
        @cache /var/cache \
        @tmp /var/tmp
}

# ////////////////////////////////////////////////////////////////////////////
# SECURE BOOT & KERNEL COMMAND LINE
# ////////////////////////////////////////////////////////////////////////////

# Whether this installation gets Secure Boot, which always means a unified
# kernel image. The boot loader and the ram disk are both built differently for
# a signed boot chain, so the rule is named once instead of repeated.
# https://wiki.archlinux.org/title/Unified_kernel_image
secure_boot_wanted() {
    [ "$ARCH_OS_SECURE_BOOT_ENABLED" = "true" ] &&
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_BOOTLOADER" = "systemd" ]
}

# The images the firmware actually starts. Named once because the initramfs task
# writes them, the boot splash rebuilds them and two tests read them back - and
# a check against the image this machine does not start from checks nothing.
boot_images() {
    if secure_boot_wanted; then
        printf '/boot/EFI/Linux/arch-%s.efi\n/boot/EFI/Linux/arch-%s-fallback.efi\n' \
            "$ARCH_OS_KERNEL" "$ARCH_OS_KERNEL"
    else
        printf '/boot/initramfs-%s.img\n/boot/initramfs-%s-fallback.img\n' \
            "$ARCH_OS_KERNEL" "$ARCH_OS_KERNEL"
    fi
}

# Read by the unified kernel image, by systemd-boot's entries and by GRUB's
# command line - three tasks, one answer, so no two of them can disagree about
# how this system boots. Why each parameter is here: docs/REFERENCE.md
kernel_args() {
    local args=(rw init=/usr/lib/systemd/systemd)

    args+=(zswap.enabled=0) # pointless next to zram, and the two interfere

    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        args+=("rd.luks.name=$(blkid -s UUID -o value "$ARCH_OS_ROOT_PARTITION")=cryptroot")
        args+=(root=/dev/mapper/cryptroot)
    else
        args+=("root=PARTUUID=$(lsblk -dno PARTUUID "$ARCH_OS_ROOT_PARTITION")")
    fi

    [ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && args+=(rootflags=subvol=@ rootfstype=btrfs)
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

# A sudo rule in the new system, as a drop-in and checked before it is trusted:
# a syntax error in /etc/sudoers locks everybody out of root.
# https://wiki.archlinux.org/title/Sudo
sudoers_rule() {
    local file="${MNT}/etc/sudoers.d/${1}"
    mkdir -p "${MNT}/etc/sudoers.d"
    printf '# Written by the Arch OS Installer.\n%s\n' "$2" >"$file"
    chmod 0440 "$file"
    arch-chroot "$MNT" visudo -cqf "/etc/sudoers.d/${1}"
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
    build="${build} && printf '\noptions=(\"!debug\")\n' >>PKGBUILD"
    # make and cargo are named separately because neither reads the other.
    build="${build} && MAKEFLAGS=-j${jobs} CARGO_BUILD_JOBS=${jobs} makepkg -si --noconfirm --needed"

    sudoers_rule 99-aur-build '%wheel ALL=(ALL:ALL) NOPASSWD: ALL'

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

    as_user "rm -rf ${dir}"
    rm -f "${MNT}/etc/sudoers.d/99-aur-build"

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

# Whether this is a booted Arch Linux live image, which is the only machine this
# module belongs on. Two markers, because either on its own is enough:
# /run/archiso is what the image mounts, archisobasedir is what it was booted
# with. And Arch on top of them, because an image built the same way by somebody
# else is not the system this installs.
arch_live() {
    { [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline; } || return 1
    grep -qs '^ID=arch$' /etc/os-release
}

# Real HTTPS to a host the installation needs anyway, not a ping - a captive
# portal answers pings too.
is_online() {
    curl -Lsf --connect-timeout 5 --max-time 15 https://archlinux.org >/dev/null
}

# The keyboard on the machine the installer runs on, loaded the moment the
# language or the keyboard is answered: until then, everything typed after it is
# typed on a layout nobody chose. A simulated run is on somebody's own machine.
load_console_keyboard() {
    [ "$DEBUG" = "true" ] && return 0
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

# The timezone the chosen country keeps, or a best guess at where this machine
# is for a locale that names none. Only ever the value the list opens on.
auto_timezone() {
    local zone
    zone="$(country_field 3 "$ARCH_OS_LOCALE_LANG")"
    [ -n "$zone" ] || zone="$(curl -sf --connect-timeout 5 --max-time 5 "http://ip-api.com/line?fields=timezone" || true)"
    printf '%s' "$zone"
}

list_countries() {
    printf 'auto\tauto — %s\n' "$(auto_country)"
    echo none
    # A "-" marks a country Arch has no mirror in.
    awk -F'\t' '!/^#/ && $2 != "-" { print $2 }' "${DATA}/countries"
}

# Whole disks only - 8 is SCSI and SATA, 259 NVMe, 254 virtual block devices.
# Nobody picks between /dev/sda and /dev/sdb by name, so the size and the model
# are what it is chosen by.
list_disks() {
    lsblk -d -n -I 8,259,254 -o PATH,SIZE,MODEL |
        awk '{ path = $1; $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# The partitions of the chosen disk, for a dual boot laid out by somebody else.
# The size, file system and label are what tell the EFI partition apart from the
# one the other operating system lives on.
list_partitions() {
    lsblk -n -o PATH,SIZE,FSTYPE,LABEL "$ARCH_OS_DISK" | tail -n +2 |
        awk '{ path = $1; $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# The first vfat partition is almost always the one the other system boots from.
default_boot_partition() {
    lsblk -n -o PATH,FSTYPE "$ARCH_OS_DISK" | awk '$2 == "vfat" { print $1; exit }'
}

# The largest partition that is not the EFI one: the likeliest candidate for
# space freed up to install into.
default_root_partition() {
    lsblk -bn -o PATH,SIZE,FSTYPE "$ARCH_OS_DISK" | tail -n +2 |
        awk '$3 != "vfat" { print $2, $1 }' | sort -rn | head -n1 | awk '{ print $2 }'
}

# Read again at install time, so answers carried to another machine still fit it.
list_microcode() {
    printf 'auto\tauto — %s\n' "$(auto_microcode)"
    echo intel-ucode
    echo amd-ucode
    echo none
}

# The desktop keyboard is asked of the running system where it can answer and
# read from data/ where it cannot: the Arch live image ships no xkeyboard-config.
list_layouts() {
    printf 'auto\tauto — %s\n' "$(auto_layout)"

    local layouts
    layouts="$(localectl list-x11-keymap-layouts 2>/dev/null)"
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

    variants="$(localectl list-x11-keymap-variants "$layout" 2>/dev/null)"
    if [ -n "$variants" ]; then
        echo "$variants"
        return 0
    fi
    grep "^${layout} " "${DATA}/x11-variants" | cut -d' ' -f2- | tr ' ' '\n'
}
