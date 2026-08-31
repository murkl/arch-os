# Shared ground for every script of this tree: the target, the values that are
# worked out rather than asked for, and the few things every task does.
#
# The runtime sources this before every task and every hook, so a script is
# plain shell with no preamble. It sets no traps and no shell options — the
# runtime already wraps each one in an ERR trap that stops at the first failure
# and reports the file, the line and the command.
#
# Nothing here prints for a person to read: stdout and stderr go to the log.

# Where the new system is mounted while it is being built.
MNT=/mnt

# The tables looked up below, beside this file.
DATA="$(dirname "${BASH_SOURCE[0]}")/data"

# Shell that knows nothing about Arch OS — DEBUG, is_online, part_of and the
# rest — sourced first so everything below can lean on it.
# shellcheck source=util.sh
source "$(dirname "${BASH_SOURCE[0]}")/util.sh"

# ─── What a language and a country imply ─────────────────────────────────────
#
# The keyboard a language is typed on, the font a console can draw it in, the
# mirrors its country has and the time zone that country keeps. None of it can
# be guessed from the shape of a locale — de_CH is not de, sv is not se, and a
# mirror list has never heard of DE — so all four are looked up in data/.
#
# The same tables fill the lists the question pages offer, so what a page shows
# beside `auto` and what a task gets can never disagree.

# A column of the data/languages row for a locale: its own row where there is
# one, otherwise its language's.
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
# Nothing for a locale that names none.
country_field() {
    local locale="${2%%.*}"
    [ "${locale#*_}" != "$locale" ] || return 0
    awk -F'\t' -v col="$1" -v code="${locale#*_}" '$1 == code { print $col }' "${DATA}/countries"
}

# The keyboard the live image was started with, if it was started with one. The
# Arch image records it in root's shell history as the loadkeys command that set
# it, which is the only place it can be read back from.
live_keymap() {
    grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ' || true
}

# ─── Values that are worked out rather than asked for ────────────────────────
#
# is_auto and not_none, used throughout this section, are defined in util.sh.

# What each list comes to when it is left on auto. Named rather than inlined
# because the question page shows the same answer beside its auto row.
auto_keymap() {
    local keymap
    keymap="$(language_field 2 "$ARCH_OS_LOCALE_LANG")"
    : "${keymap:=$(live_keymap)}"
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

# Both fall back to none rather than to nothing, because for these two none is
# the answer: no font is the console's own, and no country is every mirror in
# the world ranked by speed.
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

# The zone the chosen country keeps, and — for a locale that names none — where
# this machine appears to be, asked of the network. A guess either way, offered
# as the value the list opens on and never as an answer.
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

# Logging in automatically follows disk encryption: the disk is already unlocked
# by a password at boot, so a second one at the login screen protects nothing.
auto_autologin() { printf '%s' "${ARCH_OS_ENCRYPTION_ENABLED:-false}"; }

# ─── Disks and partitions ─────────────────────────────────────────────────────
#
# disk_options and part_of, used below, are defined in util.sh.

# How this project mounts btrfs, written down once: the installation lays the
# file system out with these and the recovery has to put it back exactly as it
# found it, so the two must never drift apart.
BTRFS_OPTS="defaults,noatime,compress=zstd"

# Resolved once here rather than in one stage, so every stage sees the same
# answer however it was arrived at.
: "${ARCH_OS_BOOT_PARTITION:=$(part_of "$ARCH_OS_DISK" 1)}"
: "${ARCH_OS_ROOT_PARTITION:=$(part_of "$ARCH_OS_DISK" 2)}"

is_auto "$ARCH_OS_VCONSOLE_KEYMAP" && ARCH_OS_VCONSOLE_KEYMAP="$(auto_keymap)"
is_auto "$ARCH_OS_VCONSOLE_FONT" && ARCH_OS_VCONSOLE_FONT="$(auto_font)"
is_auto "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" && ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="$(auto_layout)"
is_auto "$ARCH_OS_REFLECTOR_COUNTRY" && ARCH_OS_REFLECTOR_COUNTRY="$(auto_country)"
is_auto "$ARCH_OS_MICROCODE" && ARCH_OS_MICROCODE="$(auto_microcode)"
is_auto "$ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED" && ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED="$(auto_autologin)"

ARCH_OS_VCONSOLE_FONT="$(not_none "$ARCH_OS_VCONSOLE_FONT")"
ARCH_OS_REFLECTOR_COUNTRY="$(not_none "$ARCH_OS_REFLECTOR_COUNTRY")"
ARCH_OS_DESKTOP_KEYBOARD_VARIANT="$(not_none "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT")"

# Every line of /etc/locale.gen belonging to the chosen language, uncommented,
# plus English as a fallback.
locale_gen_lines() {
    sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "^${ARCH_OS_LOCALE_LANG}" || true
    echo 'en_US.UTF-8 UTF-8'
}

# The console keyboard and font of the new system, written into it.
#
# A function rather than four lines in the task that configures the system,
# because it is needed once before that: the kernel's own package hook builds a
# ram disk during pacstrap, and mkinitcpio's sd-vconsole hook reads this file
# while it does. Without it that build warns and falls back to a US layout —
# which the ram disk built later replaces, but not before the warning has sent
# somebody looking for a keyboard problem that was never there.
write_vconsole() {
    mkdir -p "${MNT}/etc"
    echo "KEYMAP=${ARCH_OS_VCONSOLE_KEYMAP}" >"${MNT}/etc/vconsole.conf"
    [ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=${ARCH_OS_VCONSOLE_FONT}" >>"${MNT}/etc/vconsole.conf"
    return 0
}

# Loading the keyboard on the machine the installer is running on, which is what
# `apply:` calls the moment the language or the keyboard itself is answered.
# Until this has run, every answer after it is typed on a layout nobody chose.
load_console_keyboard() {
    # DEBUG runs on somebody's own machine, whose keyboard is not ours to touch.
    [ "$DEBUG" = "true" ] && return 0
    loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
}

# ─── Secure Boot ─────────────────────────────────────────────────────────────

# Whether this installation gets Secure Boot, which always comes as a package
# with a Unified Kernel Image. The same rule the secure-boot task is gated by,
# in the form the boot loader and the initial ram disk need: both are built
# differently for a signed boot chain, and both run either way.
#
# Tied to disk encryption on systemd-boot for three reasons:
#   - Without encryption, Secure Boot guards a boot chain whose data an attacker
#     simply reads off the drive instead. The two only add up together.
#   - A UKI holds kernel, initramfs and command line in one signed binary.
#     Signing only kernel and boot loader would leave the initramfs on the
#     unencrypted EFI partition forgeable — and a forged initramfs collects the
#     passphrase, which is the attack this is supposed to stop.
#   - GRUB is left out on purpose: its EFI binary is generated by grub-install,
#     so it would need re-signing after every update, and no hook does that.
secure_boot_wanted() {
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_BOOTLOADER" = "systemd" ]
}

# Whether the firmware is in setup mode — the only state our own keys may be
# enrolled in. "Secure Boot disabled" is not the same thing: the vendor keys are
# usually still in place. Read from the UEFI variable rather than parsed out of
# `sbctl status`, whose output is meant for humans: the first four bytes are
# attributes, the fifth holds the value.
# What mkinitcpio builds for this system, as paths inside it: two unified kernel
# images where the boot chain is signed, and the two plain ram disks everywhere
# else. Named here because two tasks have to agree about it — the one that sets
# the preset up, and the one that checks what came out of it.
kernel_images() {
    if secure_boot_wanted; then
        echo "/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi"
        echo "/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}-fallback.efi"
        return 0
    fi
    echo "/boot/initramfs-${ARCH_OS_KERNEL}.img"
    echo "/boot/initramfs-${ARCH_OS_KERNEL}-fallback.img"
}

secure_boot_setup_mode() {
    local efivar=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
    [ -r "$efivar" ] || return 1
    [ "$(od -An -t u1 -j 4 -N 1 "$efivar" 2>/dev/null | tr -d ' ')" = "1" ]
}

# ─── The kernel command line ─────────────────────────────────────────────────

# Written once and read by both the boot entries and the unified kernel image,
# so the two can never disagree about how this system boots.
kernel_args() {
    local args=(rw init=/usr/lib/systemd/systemd)

    # zswap is pointless next to zram and the two interfere.
    args+=(zswap.enabled=0)

    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        args+=("rd.luks.name=$(blkid -s UUID -o value "$ARCH_OS_ROOT_PARTITION")=cryptroot")
        args+=(root=/dev/mapper/cryptroot)
    else
        args+=("root=PARTUUID=$(lsblk -dno PARTUUID "$ARCH_OS_ROOT_PARTITION")")
    fi

    [ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && args+=(rootflags=subvol=@ rootfstype=btrfs)
    [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ] && args+=(nowatchdog)

    # A quiet boot, so the splash is not written over by kernel messages.
    # https://wiki.archlinux.org/title/Silent_boot
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ]; then
        args+=(quiet splash vt.global_cursor_default=0 loglevel=3 rd.udev.log_level=3 systemd.show_status=auto)
    fi

    [ -n "$ARCH_OS_KERNEL_ARGS" ] && args+=("$ARCH_OS_KERNEL_ARGS")
    printf '%s' "${args[*]}"
}

# ─── Installing into the new system ──────────────────────────────────────────

# Package installs are retried: the one thing that reliably goes wrong during an
# installation is the network, and losing twenty minutes of work to a mirror
# that blinked would be absurd.
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

chroot_pacman_remove() { arch-chroot "$MNT" pacman -Rn --noconfirm "$@"; }

# Building from the AUR needs a normal user who may use sudo without a password.
# It is granted for exactly the length of the build and taken back after —
# including when the build fails, which is why the revoking is not left to the
# end of the function.
chroot_aur_install() {
    local repo="$1"
    local url="https://aur.archlinux.org/${repo}.git"
    local dir status=1 i
    dir="$(mktemp -u "/home/${ARCH_OS_USERNAME}/.aur-${repo}.XXXX")"

    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' "${MNT}/etc/sudoers"

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
    sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' "${MNT}/etc/sudoers"

    [ "$status" -eq 0 ] || echo "building ${repo} from the AUR failed after ${RETRIES} attempts" >&2
    return "$status"
}

# as_user runs a command inside the new system as the account being created,
# which is what makepkg insists on and what anything writing into that home
# directory should do anyway.
as_user() {
    arch-chroot "$MNT" /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "$1"
}

# ─── The first login ─────────────────────────────────────────────────────────

# A few desktop settings can only be applied by the user's own session, because
# they live in that session's settings database and there is no session yet.
# Tasks append lines here; the first-login task turns whatever collected into a
# script that runs once, at the first login, and then removes itself.
FIRST_LOGIN="${MNT}/home/${ARCH_OS_USERNAME}/.first-login"

on_first_login() { cat >>"$FIRST_LOGIN"; }

# ─── Sharing what was answered ───────────────────────────────────────────────
#
# An installation is two dozen answers, and the second machine set up the same
# way is otherwise two dozen answers given again by hand. So the finished
# configuration is put somewhere a phone can reach and the address of it is
# shown at the end of the run; the other end of the same idea is the starting
# point that takes its answers from such an address instead of from this tree.
#
# It is only ever the answer file: names, a host name, a disk, a language. The
# password is not in it — the runtime never writes a secret down — and neither
# is the log.

# Where a configuration is shared. paste.rs takes a file over an ordinary POST,
# answers with the address it now lives at, and serves it back as plain text —
# no account, no key, nothing to agree to. Everything it does not do is a thing
# that cannot break.
CONFIG_SERVICE="https://paste.rs"

# The address a shared configuration lives at, from whatever somebody has in
# front of them: the whole link, or only the code at the end of it. They are the
# same thing said differently, and asking which one they are holding would be a
# question about our storage rather than about their installation.
config_url() {
    local ref
    ref="$(printf '%s' "$1" | tr -d '[:space:]')"
    case "$ref" in
    http://* | https://*) printf '%s' "$ref" ;;
    *) printf '%s/%s' "$CONFIG_SERVICE" "${ref##*/}" ;;
    esac
}

# The answers as somebody else should read them: everything this installation
# was told, without the lines about the sharing itself. A configuration naming
# where an earlier copy of it went would send whoever opened it somewhere else
# again.
shareable_config() {
    grep -v '^ARCH_OS_CONFIG_' "$INSTALLER_CONF" || true
}

# The answers, put where a camera can reach them, and the address kept as an
# answer of its own — which is what puts it on the page at the end of the run
# and into the copy inside the new system.
#
# Nothing here may fail the installation. The system on the disk is finished by
# the time this runs, and a pastebin that was unreachable says nothing at all
# about it: a failure is a line in the log, an address that stays empty, and a
# page with no code on it.
share_config() {
    # Simulated, this still answers with an address. The page at the end of a
    # run is the thing most worth looking at while this tree is being worked on,
    # and a page with nothing on it cannot be looked at.
    simulating && {
        answer ARCH_OS_CONFIG_URL "${CONFIG_SERVICE}/demo"
        return 0
    }

    local url
    if ! url="$(shareable_config | curl -sf --connect-timeout 10 --max-time 30 --data-binary @- "${CONFIG_SERVICE}/")"; then
        echo "the configuration could not be shared" >&2
        return 0
    fi
    url="$(printf '%s' "$url" | tr -d '[:space:]')"
    [ -n "$url" ] && answer ARCH_OS_CONFIG_URL "$url"
    return 0
}

# A configuration somebody shared, taken as the answers to this installation.
#
# What the runtime owns is left where it is: which language this interface is
# read in and what this run is doing are settings of the program in front of
# you, not of a system installed on somebody else's machine. So is the sharing.
#
# This one may fail, and says why in a sentence: it runs while somebody is
# looking at the box they typed the code into, and there is nothing to do about
# a wrong code but read that and try another.
import_config() {
    local url body
    url="$(config_url "$ARCH_OS_CONFIG_SOURCE")"

    if ! body="$(curl -Lsf --connect-timeout 10 --max-time 30 "$url")"; then
        echo "Nothing could be read at ${url}" >&2
        return 1
    fi
    body="$(printf '%s\n' "$body" | grep '^ARCH_OS_[A-Z0-9_]*=' | grep -v '^ARCH_OS_CONFIG_' || true)"
    if [ -z "$body" ]; then
        echo "What is kept at ${url} is not an Arch OS configuration" >&2
        return 1
    fi
    printf '%s\n' "$body" >>"$INSTALLER_CONF"
}

# ─── Leaving ─────────────────────────────────────────────────────────────────

# Everything the installation mounted, taken back down in the right order. Used
# by the task that only unmounts, by the one that restarts, and by the hooks
# below, so none of them can ever do it differently.
#
# Written to the disk before anything is taken down, so a target that will not
# unmount is a mount left standing rather than a file half written. The second
# go is deliberately unguarded: a target still held after everything using it
# was killed is a real failure and belongs on the screen with the command that
# hit it.
unmount_target() {
    swapoff -a || true
    sync
    if ! umount -A -R "$MNT"; then
        free_target
        umount -A -R "$MNT"
    fi
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot
    echo "unmounted"
}

# Whatever still has the target open, named in the log and then killed. Once the
# tasks are done nothing on this machine has any business inside the new system,
# so what turns up here is a process a package hook or a chroot left running —
# and the pause is what the kernel needs to let go of its files afterwards.
#
# -M is the whole safety of it: without it, a target that is not a mount point
# resolves to the file system containing it, which on the live image is the live
# image — and the kill would take this installer and everything else with it.
free_target() {
    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2
}

# What the restart and shutdown hooks do. Whatever the installation had mounted
# is closed first, so a machine restarted halfway through a run does not take a
# half-written file system down with it — and nothing mounted is not an error,
# since the question is as likely to be asked before the first task as after the
# last.
leave_machine() {
    simulating && return 0
    if [ "$INSTALLER_MODE" = "recovery" ]; then
        recovery_unmount || true
    else
        unmount_target || true
    fi
    systemctl "$1"
}

# ─── The recovery ────────────────────────────────────────────────────────────

# The other thing this tree does, kept in a file of its own: everything above is
# what an installation shares, everything there is what a recovery shares, and
# the two only meet in MNT and in the handful of helpers above.
#
# Sourced last, so it can use them. Nothing declares it — it is beside this file
# under its own name, the way everything else in this tree is found.
# shellcheck source=recovery.sh
source "$(dirname "${BASH_SOURCE[0]}")/recovery.sh"
