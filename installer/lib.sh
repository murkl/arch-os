# Shared ground for every script of this tree: the target, the values worked out
# rather than asked for, and the few things every task does.
#
# Everything else lives in the task that does it. What is here is here because
# several scripts need the same answer and must not disagree about it — a boot
# entry and a unified kernel image that describe different command lines are a
# system that boots one way and updates the other.
#
# The runtime sources this before every task and every hook, so a script is plain
# shell with no preamble — the ERR trap that stops at the first failure is the
# runtime's. Nothing here prints for a person to read; stdout goes to the log.

# Where the new system is mounted while it is being built.
MNT=/mnt

# The tables looked up below, beside this file.
DATA="$(dirname "${BASH_SOURCE[0]}")/data"

# ─── Simulation ──────────────────────────────────────────────────────────────

# DEBUG=true runs the installer without touching the machine. Each task guards
# itself with `simulating && return 0` as its first line, so a unit is only ever
# skipped as a whole.
: "${DEBUG:=false}"

simulating() {
    [ "$DEBUG" = "true" ] || return 1
    echo "simulated: ${BASH_SOURCE[1]}"
    sleep 1 # so the unit is visible in the interface rather than flashing past
}

# ─── Network ─────────────────────────────────────────────────────────────────

# Real HTTPS to a host the installation needs anyway, not a ping — a captive
# portal answers pings.
is_online() {
    curl -Lsf --connect-timeout 5 --max-time 15 https://archlinux.org >/dev/null
}

# ─── Where a task lives ──────────────────────────────────────────────────────

# The folder of the task that called it, where a unit keeps the files it ships
# with.
where() { dirname "${BASH_SOURCE[1]}"; }

# ─── What a language and a country imply ─────────────────────────────────────
#
# The keyboard a language is typed on, the font that can draw it, the mirrors its
# country has, the time zone it keeps. None of it follows from the shape of a
# locale — de_CH is not de, sv is not se — so all four are looked up in data/.
# The same tables fill the lists the question pages offer.

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

# ─── auto / none ─────────────────────────────────────────────────────────────

# The two words the lists in installer.yaml share; neither ever reaches a task.
# auto is a value still to be found, none is the empty answer said out loud.
is_auto() { [ -z "$1" ] || [ "$1" = "auto" ]; }
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# ─── Values that are worked out rather than asked for ────────────────────────

# What each list comes to on auto. Named rather than inlined, because the
# question page shows the same answer beside its auto row.
auto_keymap() {
    local keymap
    keymap="$(language_field 2 "$ARCH_OS_LOCALE_LANG")"
    # Otherwise the keyboard the live image was started with. The Arch image
    # records it in root's shell history as the loadkeys command that set it,
    # which is the only place it can be read back from.
    : "${keymap:=$(grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null |
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

# Both fall back to none rather than to nothing: no font is the console's own,
# and no country is every mirror in the world ranked by speed.
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

# The zone the chosen country keeps, or — for a locale naming none — where this
# machine appears to be. A guess either way, offered as the value the list opens
# on and never as an answer.
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

# Automatic login follows disk encryption: the disk is already unlocked by a
# password at boot, so a second one at the login screen protects nothing.
auto_autologin() { printf '%s' "${ARCH_OS_ENCRYPTION_ENABLED:-false}"; }

# ─── Where the new system goes ───────────────────────────────────────────────

# part_of names a partition of a disk. Devices whose name ends in a digit —
# nvme0n1, mmcblk0, loop0 — put a p between the disk and the number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

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

# ─── The console of the new system ───────────────────────────────────────────

# The console keyboard and font of the new system.
#
# A function rather than four lines in configure-system, because it is needed
# once before that: the kernel's package hook builds a ram disk during pacstrap,
# and mkinitcpio's sd-vconsole hook reads this file while it does.
write_vconsole() {
    mkdir -p "${MNT}/etc"
    echo "KEYMAP=${ARCH_OS_VCONSOLE_KEYMAP}" >"${MNT}/etc/vconsole.conf"
    [ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=${ARCH_OS_VCONSOLE_FONT}" >>"${MNT}/etc/vconsole.conf"
    return 0
}

# The keyboard on the machine the installer runs on, which `apply:` calls the
# moment the language or the keyboard is answered. Until it has run, everything
# after it is typed on a layout nobody chose.
load_console_keyboard() {
    # DEBUG runs on somebody's own machine, whose keyboard is not ours to touch.
    [ "$DEBUG" = "true" ] && return 0
    loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
}

# ─── The signed boot chain ───────────────────────────────────────────────────

# Whether this installation gets Secure Boot, which always comes with a unified
# kernel image. The boot loader and the ram disk are both built differently for a
# signed boot chain and both run either way, so the rule is named once.
#
# Only offered with encryption and systemd-boot:
#   - Without encryption an attacker reads the data off the drive instead.
#   - A UKI signs kernel, initramfs and command line together. Signing only the
#     kernel would leave a forgeable initramfs on the unencrypted EFI partition,
#     and a forged initramfs collects the passphrase.
#   - GRUB's EFI binary is generated by grub-install, so it would need re-signing
#     after every update and no hook does that.
secure_boot_wanted() {
    [ "$ARCH_OS_SECURE_BOOT_ENABLED" = "true" ] &&
        [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_BOOTLOADER" = "systemd" ]
}

# ─── The kernel command line ─────────────────────────────────────────────────

# Read by both the boot entries and the unified kernel image, so the two cannot
# disagree about how this system boots.
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
# installation is the network.
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

# A sudo rule in the new system, as a drop-in. /etc/sudoers belongs to the sudo
# package, and a syntax error in it locks everybody out of root — so rules go
# beside it, one file each, checked before they are believed.
sudoers_rule() {
    local file="${MNT}/etc/sudoers.d/${1}"
    mkdir -p "${MNT}/etc/sudoers.d"
    printf '# Written by the Arch OS Installer.\n%s\n' "$2" >"$file"
    chmod 0440 "$file"
    arch-chroot "$MNT" visudo -cqf "/etc/sudoers.d/${1}"
}

# Building from the AUR needs a normal user who may use sudo without a password.
# It is granted for exactly the length of the build and taken back after —
# including when the build fails, which is why the revoking is not left to the
# end of the function.
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

# as_user runs a command inside the new system as the account being created,
# which is what makepkg insists on and what anything writing into that home
# directory should do anyway.
as_user() {
    arch-chroot "$MNT" /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "$1"
}

# ─── The first login ─────────────────────────────────────────────────────────

# Some desktop settings live in the user's own settings database, and there is no
# session yet. Tasks append lines here; the first-login task turns them into a
# script that runs once at the first login and then removes itself.
FIRST_LOGIN="${MNT}/home/${ARCH_OS_USERNAME}/.first-login"

on_first_login() { cat >>"$FIRST_LOGIN"; }

# ─── Leaving ─────────────────────────────────────────────────────────────────

# Everything the installation mounted, taken back down in the right order —
# named once, so the unmount task, the restart and the shutdown cannot differ.
#
# Flushed before anything comes down, so a target that will not unmount is a
# mount left standing rather than a file half written. The second attempt is
# unguarded on purpose: that one is a real failure.
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

# Whatever still has the target open, named in the log and then killed — a
# process a package hook or a chroot left running. The pause is what the kernel
# needs to let go of its files afterwards.
#
# -M is the whole safety of it: without it a target that is not a mount point
# resolves to the file system containing it, which on the live image is the live
# image itself.
free_target() {
    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2
}
