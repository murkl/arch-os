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

# The folder of the task that called it, where a unit keeps the files it ships
# with.
where() { dirname "${BASH_SOURCE[1]}"; }

# ─── Simulation ──────────────────────────────────────────────────────────────

# DEBUG=true runs the whole installer without touching the machine: every wall
# steps aside and every task reports success without doing anything. Each task
# guards itself with `simulating && return 0` as its first line, so a unit can
# only ever be skipped as a whole.
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
# `auto` and `none` are the two words the lists in installer.yaml share, and
# neither ever reaches a task. They are not the same test: auto is a value still
# to be found, none is the value itself — the empty answer said out loud.

is_auto() { [ -z "$1" ] || [ "$1" = "auto" ]; }
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

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

# Every line of /etc/locale.gen belonging to the chosen language, uncommented,
# plus English as a fallback.
locale_gen_lines() {
    sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "^${ARCH_OS_LOCALE_LANG}" || true
    echo 'en_US.UTF-8 UTF-8'
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

# ─── Leaving ─────────────────────────────────────────────────────────────────

# Everything the installation mounted, taken back down in the right order. Used
# by the task that only unmounts, by the one that restarts, and by the hooks
# below, so none of them can ever do it differently.
unmount_target() {
    swapoff -a || true
    umount -A -R "$MNT"
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot
    echo "unmounted"
}

# What the restart and shutdown hooks do. Whatever the installation had mounted
# is closed first, so a machine restarted halfway through a run does not take a
# half-written file system down with it — and nothing mounted is not an error,
# since the question is as likely to be asked before the first task as after the
# last.
leave_machine() {
    simulating && return 0
    unmount_target || true
    systemctl "$1"
}
