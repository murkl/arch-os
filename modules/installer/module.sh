# THE MODULE'S SHELL | Sourced by Oak in front of everything this module runs
#
# Every task, and every piece of shell module.yaml writes for a list, a
# suggestion or a check, is given this file first - so a function named here is
# called from the yaml by name.
#
# Only what more than one script must agree about belongs in it: a boot entry
# and a unified kernel image built from two different command lines would be a
# system that boots one way and updates itself another. Anything one task needs
# stays in that task. Nothing here prints for a person to read, only to the log.

# Where the new system is mounted while it is being built.
MNT=/mnt

# The lookup tables used below, next to this file.
DATA="$(dirname "${BASH_SOURCE[0]}")/data"

# The folder of the task that called it, where a unit keeps the files it ships with.
where() { dirname "${BASH_SOURCE[1]}"; }

# ////////////////////////////////////////////////////////////////////////////
# SIMULATION & NETWORK
# ////////////////////////////////////////////////////////////////////////////

# --debug runs without touching the machine. Each task guards itself with
# `simulating && return 0` as its first line, so a unit is only ever skipped as
# a whole, and each test with `debugging && return 0` — a simulated run wrote
# nothing, so there is nothing on the machine for it to read.
#
# The pause is the difference between the two: it holds a step on screen long
# enough to be read instead of flashing past, and a test is not a step anybody
# is watching.

debugging() { [ "$DEBUG" = "true" ]; }

simulating() {
    debugging || return 1
    echo "simulated" # Oak has already logged which step this is
    sleep 1          # keep the step visible in the interface instead of flashing past
}

# ----------------------------------------------------------------------------

# Real HTTPS to a host the installation needs anyway, not a ping - a captive
# portal answers pings too.
is_online() {
    curl -Lsf --connect-timeout 5 --max-time 15 https://archlinux.org >/dev/null
}

# ////////////////////////////////////////////////////////////////////////////
# LOCALE LOOKUP & AUTO VALUES
# ////////////////////////////////////////////////////////////////////////////

# Keyboard, font, mirror country and timezone don't follow from the shape of a
# locale - de_CH is not de, sv is not se - so all four are looked up in data/.
# The same tables fill the lists the question pages offer.

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

# A column of the data/countries row for the territory a locale ends in.
# Empty for a locale that names none.
country_field() {
    local locale="${2%%.*}"
    [ "${locale#*_}" != "$locale" ] || return 0
    awk -F'\t' -v col="$1" -v code="${locale#*_}" '$1 == code { print $col }' "${DATA}/countries"
}

# ----------------------------------------------------------------------------

# The two magic words the lists in module.yaml share; neither ever reaches a
# task. auto means "not answered yet, work it out"; none means "answered: empty".
is_auto() { [ -z "$1" ] || [ "$1" = "auto" ]; }
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# ----------------------------------------------------------------------------

# What each list resolves to on auto. Functions rather than inlined, because the
# question page shows the same answer next to its auto row.
auto_keymap() {
    local keymap
    keymap="$(language_field 2 "$ARCH_OS_LOCALE_LANG")"
    # Fall back to the keyboard the live image was started with. The Arch
    # image only records it as the loadkeys command in root's shell history,
    # so that's the one place it can be read back from. Finding nothing there
    # is the ordinary case on a machine that has none, so the grep is not
    # allowed to make a failure of it - pipefail would carry that out of the
    # whole lookup.
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

# Both fall back to none rather than to an empty string: no font means the
# console keeps its own, no country means every mirror ranked by speed.
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

# The timezone the chosen country keeps, or a best guess at where this machine
# is for a locale that names no country. Only ever offered as the value a list
# opens on, never taken as the answer.
auto_timezone() {
    local zone
    zone="$(country_field 3 "$ARCH_OS_LOCALE_LANG")"
    [ -n "$zone" ] || zone="$(curl -sf --connect-timeout 5 --max-time 5 "http://ip-api.com/line?fields=timezone" || true)"
    printf '%s' "$zone"
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
# THE QUESTIONS | What module.yaml calls by name
# ////////////////////////////////////////////////////////////////////////////

# Every list a question offers and every value one opens on. They live here
# rather than in module.yaml because a page of awk inside a yaml scalar is read
# by nobody and checked by nothing, and because the auto rows below are the
# lookups above said a second way.
#
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

list_countries() {
    printf 'auto\tauto — %s\n' "$(auto_country)"
    echo none
    # A "-" marks a country Arch has no mirror in.
    awk -F'\t' '!/^#/ && $2 != "-" { print $2 }' "${DATA}/countries"
}

# Read again at install time, so answers carried to another machine still fit it.
list_microcode() {
    printf 'auto\tauto — %s\n' "$(auto_microcode)"
    echo intel-ucode
    echo amd-ucode
    echo none
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

# ----------------------------------------------------------------------------

# The desktop keyboard is asked of the running system where it can answer and
# read from data/ where it cannot: the Arch live image ships no
# xkeyboard-config.

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

# ////////////////////////////////////////////////////////////////////////////
# TARGET DISK & CONSOLE
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

# Autologin follows disk encryption: the disk is already unlocked by a password
# at boot, so a second one at the login screen protects nothing.
is_auto "$ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED" && ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED="${ARCH_OS_ENCRYPTION_ENABLED:-false}"

ARCH_OS_VCONSOLE_FONT="$(not_none "$ARCH_OS_VCONSOLE_FONT")"
ARCH_OS_REFLECTOR_COUNTRY="$(not_none "$ARCH_OS_REFLECTOR_COUNTRY")"
ARCH_OS_DESKTOP_KEYBOARD_VARIANT="$(not_none "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT")"

# ----------------------------------------------------------------------------

# The console keyboard and font of the new system. A function rather than four
# lines in configure-system, because it is needed before that runs: mkinitcpio's
# sd-vconsole hook reads this file while pacstrap builds the ram disk.
write_vconsole() {
    mkdir -p "${MNT}/etc"
    echo "KEYMAP=${ARCH_OS_VCONSOLE_KEYMAP}" >"${MNT}/etc/vconsole.conf"
    [ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=${ARCH_OS_VCONSOLE_FONT}" >>"${MNT}/etc/vconsole.conf"
    return 0
}

# The keyboard on the machine the installer runs on, called by `apply:` the
# moment the language or the keyboard is answered. Until this has run,
# everything typed after it is typed on a layout nobody chose.
load_console_keyboard() {
    # A simulated run is on somebody's own machine, whose keyboard is not ours
    # to touch.
    [ "$DEBUG" = "true" ] && return 0
    loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
}

# ////////////////////////////////////////////////////////////////////////////
# SECURE BOOT & KERNEL COMMAND LINE
# ////////////////////////////////////////////////////////////////////////////

# Whether this installation gets Secure Boot, which always means a unified
# kernel image. The boot loader and the ram disk are both built differently
# for a signed boot chain, so this rule is named once instead of repeated.
#
# Only offered together with encryption and systemd-boot:
#   - Without encryption an attacker just reads the data off the drive instead.
#   - A UKI signs kernel, initramfs and command line together. Signing only
#     the kernel would leave a forgeable initramfs on the unencrypted EFI
#     partition, and a forged initramfs is how the passphrase gets stolen.
#   - GRUB's EFI binary is generated by grub-install, so it would need
#     re-signing after every update, and no hook does that.
secure_boot_wanted() {
    [ "$ARCH_OS_SECURE_BOOT_ENABLED" = "true" ] &&
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_BOOTLOADER" = "systemd" ]
}

# ----------------------------------------------------------------------------

# The images the firmware actually starts: the signed unified pair where the
# boot chain is signed, the plain ram disks where it is not. Named once because
# the boot loader writes them, the boot splash rebuilds them, and three tests
# read them back - and a check against the image this machine does not start
# from is a check of nothing.
boot_images() {
    if secure_boot_wanted; then
        printf '/boot/EFI/Linux/arch-%s.efi\n/boot/EFI/Linux/arch-%s-fallback.efi\n' \
            "$ARCH_OS_KERNEL" "$ARCH_OS_KERNEL"
    else
        printf '/boot/initramfs-%s.img\n/boot/initramfs-%s-fallback.img\n' \
            "$ARCH_OS_KERNEL" "$ARCH_OS_KERNEL"
    fi
}

# ----------------------------------------------------------------------------

# Read by both the boot entries and the unified kernel image, so the two can
# never disagree about how this system boots.
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

    # Quiet boot, so the splash isn't written over by kernel messages.
    # https://wiki.archlinux.org/title/Silent_boot
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ]; then
        args+=(quiet splash vt.global_cursor_default=0 loglevel=3 rd.udev.log_level=3 systemd.show_status=auto)
    fi

    # Plymouth forces its text plugin the moment it finds a serial console, and
    # never looks for a screen at all after that: no splash, and the passphrase
    # asked in plain type. A virtual machine is handed one without asking - OVMF
    # appends console=uart,io,0x3f8 through an SMBIOS string - and so is any
    # machine administered over a serial line. Nothing is lost by ignoring them
    # here: systemd goes on writing to every console it was given either way.
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then
        args+=(plymouth.ignore-serial-consoles)
    fi

    [ -n "$ARCH_OS_KERNEL_ARGS" ] && args+=("$ARCH_OS_KERNEL_ARGS")
    printf '%s' "${args[*]}"
}

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING INTO THE NEW SYSTEM
# ////////////////////////////////////////////////////////////////////////////

# Package installs are retried: the one thing that reliably goes wrong during
# an installation is the network.
RETRIES=5
RETRY_WAIT=10

chroot_pacman_install() {
    local i
    for ((i = 1; i <= RETRIES; i++)); do
        [ "$i" -gt 1 ] && echo "retry ${i}/${RETRIES}: pacman -S $*"
        if arch-chroot "$MNT" pacman -S --noconfirm --needed --disable-download-timeout "$@"; then
            return 0
        fi
        sleep "$RETRY_WAIT"
    done
    echo "pacman failed after ${RETRIES} attempts: $*" >&2
    return 1
}

# ----------------------------------------------------------------------------

# A sudo rule in the new system, as a drop-in. /etc/sudoers belongs to the sudo
# package and a syntax error in it locks everybody out of root, so rules go
# beside it instead, one file each, checked before they're trusted.
sudoers_rule() {
    local file="${MNT}/etc/sudoers.d/${1}"
    mkdir -p "${MNT}/etc/sudoers.d"
    printf '# Written by the Arch OS Installer.\n%s\n' "$2" >"$file"
    chmod 0440 "$file"
    arch-chroot "$MNT" visudo -cqf "/etc/sudoers.d/${1}"
}

# Building from the AUR needs a normal user allowed to sudo without a password.
# Granted for the length of the build and taken back afterwards, including when
# the build fails.
chroot_aur_install() {
    local repo="$1"
    local url="https://aur.archlinux.org/${repo}.git"
    local dir status=1 i
    dir="$(mktemp -u "/home/${ARCH_OS_USERNAME}/.aur-${repo}.XXXX")"

    sudoers_rule 99-aur-build '%wheel ALL=(ALL:ALL) NOPASSWD: ALL'

    for ((i = 1; i <= RETRIES; i++)); do
        [ "$i" -gt 1 ] && echo "retry ${i}/${RETRIES}: building ${repo} from the AUR"
        if as_user "rm -rf ${dir} && git clone ${url} ${dir}" &&
            as_user "cd ${dir} && printf '\noptions=(\"!debug\")\n' >>PKGBUILD" &&
            as_user "cd ${dir} && makepkg -si --noconfirm --needed"; then
            status=0
            break
        fi
        sleep "$RETRY_WAIT"
    done

    as_user "rm -rf ${dir}"
    rm -f "${MNT}/etc/sudoers.d/99-aur-build"

    [ "$status" -eq 0 ] || echo "building ${repo} from the AUR failed after ${RETRIES} attempts" >&2
    return "$status"
}

# A command inside the new system, as the account being created - what makepkg
# insists on, and what anything writing into that home should do anyway.
as_user() {
    arch-chroot "$MNT" /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "$1"
}

# The new home, given back to the account it belongs to. Everything written from
# out here belongs to root until this has run, and a home the user cannot write
# to is a desktop that comes up broken.
own_home() {
    arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
}

# ----------------------------------------------------------------------------

# Whether the new system has a command, which is what a test asks after
# installing one. Read off the mounted tree rather than looked up inside it:
# `command -v` is a shell builtin and arch-chroot execs a binary, so that lookup
# ends in "chroot: failed to run command 'command'" whatever is installed. Arch
# puts every binary in /usr/bin - /bin, /sbin and /usr/sbin are symlinks to it.
has_command() { [ -x "${MNT}/usr/bin/${1}" ]; }

# ////////////////////////////////////////////////////////////////////////////
# FIRST LOGIN
# ////////////////////////////////////////////////////////////////////////////

# Some desktop settings only live in the user's own settings database, and there
# is no session yet to write them into. Tasks append lines here; the first-login
# task turns them into a script that runs once and then removes itself.
#
# Where the three pieces of that end up follows the XDG base directory
# specification, which is also what keeps them clear of ~/.arch-os - that
# folder belongs to the manager, and a file of ours among its bin, config and
# database is a file it may one day tidy away.
#   https://specifications.freedesktop.org/basedir-spec/latest/
#   https://specifications.freedesktop.org/autostart-spec/latest/
HOME_DIR="${MNT}/home/${ARCH_OS_USERNAME}"

# Only while the run is on; the finish-system task turns it into the three
# below, which is what the finished system keeps.
FIRST_LOGIN="${HOME_DIR}/.first-login"

# Shellcheck reads this file on its own and cannot see that Oak sources it in
# front of every task and every test, so each of the three looks unused here.
# shellcheck disable=SC2034
FIRST_LOGIN_SCRIPT="${HOME_DIR}/.local/share/arch-os/first-login.sh"
# Relative, because it is the account itself that writes it, from its own home.
# shellcheck disable=SC2034
FIRST_LOGIN_LOG=".local/state/arch-os/first-login.log"
# shellcheck disable=SC2034
FIRST_LOGIN_ENTRY="${HOME_DIR}/.config/autostart/arch-os-first-login.desktop"

on_first_login() { cat >>"$FIRST_LOGIN"; }

# ////////////////////////////////////////////////////////////////////////////
# CLOSING THE TARGET
# ////////////////////////////////////////////////////////////////////////////

# Everything under /mnt, taken back down. Nothing mounted is not an error: this
# runs before the first partition is made as well as after the last file is
# written. Whatever still holds the target is named in the log and then killed,
# and the second attempt is left unguarded on purpose - that one is a real
# failure.
#
# -R and not -A: -A reads the target as "every mount point of this file system,
# wherever it is", which is more than was asked for and more than this has any
# business taking down. -R is the target and what is mounted underneath it.
#
# -M carries the whole safety of the two fuser lines: without it a target that
# isn't itself a mount point resolves to the file system containing it, which on
# the live image is the live image itself.
unmount_target() {
    mountpoint -q "$MNT" || return 0
    umount -R "$MNT" && return 0

    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel needs a moment to actually let go of the files

    umount -R "$MNT"
}

# The target closed for good: swap off, everything unmounted and the encrypted
# volume locked again - named once so the init task, the unmount task, the
# restart and the shutdown can't disagree. Flushed first, so a target that
# refuses to unmount is a mount left standing rather than a file half written.
# The volume is closed on finding it open rather than on the answer, since a
# previous attempt leaves one open whatever this run was told.
close_target() {
    swapoff -a || true
    sync
    unmount_target || return 1 # a target still standing cannot be locked either
    [ -e /dev/mapper/cryptroot ] && cryptsetup close cryptroot
    echo "closed ${MNT}"
}
