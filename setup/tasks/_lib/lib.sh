# Shared ground for every task: the target, the values that are worked out
# rather than asked for, and the three or four things every task does.
#
# The runtime sources this before every script of this tree — see `lib:` in
# installer.yaml — so a task is plain shell with no preamble of its own. It
# sets no traps and no shell options: the runtime already wraps every script in
# an ERR trap that stops at the first real failure and reports the file, the
# line and the command.
#
# Nothing in here prints for a person to read. Everything on stdout and stderr
# goes to the log; the interface shows the name of the task and nothing else.

# Where the new system is mounted while it is being built.
MNT=/mnt

# The tables this file looks things up in, beside itself.
DATA="$(dirname "${BASH_SOURCE[0]}")/data"

# where is the folder of the task that called it: a unit keeps the files it
# ships with beside its own script, and this is how it reaches them.
where() { dirname "${BASH_SOURCE[1]}"; }

# ─── Simulation ──────────────────────────────────────────────────────────────

# DEBUG=true runs the whole installer without touching the machine: the preflight
# walls step aside and every task reports success without doing anything. It
# is how the questions, the wording and the order of the tasks are tried out
# on an ordinary running system — it installs nothing.
#
# Every task guards itself with `simulating && return 0` as its first line,
# so a unit can only ever be skipped as a whole and never halfway.
: "${DEBUG:=false}"

simulating() {
    [ "$DEBUG" = "true" ] || return 1
    echo "simulated: ${BASH_SOURCE[1]}"
    sleep 1 # so the unit is visible in the interface rather than flashing past
}

# ─── What a language implies ─────────────────────────────────────────────────
#
# A language is not only what the system speaks. It is the keyboard it is typed
# on, the font a text console can draw it in, the country its packages come from
# and the time zone that country keeps — and none of those can be guessed from
# the name of a locale: de_CH is not de, sv is not se, and Germany is not DE to a
# mirror list.
#
# So they are looked up in _lib/data, which is also where the question pages get
# what they offer. Each stays a variable anyone can answer outright.

# The row of data/languages that fits a locale: the one for the whole locale if
# there is one, otherwise the one for the language in front of it.
language_row() {
    local locale="${1%%.*}"
    awk -v locale="$locale" -v lang="${locale%%_*}" '
        /^#/ || NF == 0 { next }
        $1 == locale { hit = $0; exit }
        $1 == lang && lang_hit == "" { lang_hit = $0 }
        END { print (hit != "" ? hit : lang_hit) }
    ' "${DATA}/languages"
}

# What that row says, by column.
language_field() { language_row "$2" | awk -v n="$1" '{ print $n }'; }

language_keymap() { language_field 2 "$1"; }
language_layout() { language_field 3 "$1"; }
language_font() { language_field 4 "$1"; }

# The mirror country a locale's territory belongs to, spelled as the mirror list
# spells it. Nothing for a locale that names no territory, or one Arch has no
# mirror in — which is an answer in itself: ranking the world beats ranking a
# country with nothing in it.
language_country() {
    local locale="${1%%.*}"
    [ "${locale#*_}" != "$locale" ] || return 0
    awk -F'\t' -v code="${locale#*_}" '$1 == code { print $2 }' "${DATA}/countries"
}

# The time zone the country behind a locale keeps, from the same table the first
# question offers its countries from. Nothing — and a failure rather than an
# empty line — for a locale no country there named, which is what puts the
# network guess behind it rather than beside it.
region_timezone() {
    local zone
    zone="$(awk -F'\t' -v locale="${1%%.*}" '$1 == locale { print $2 }' "${DATA}/regions")"
    [ -n "$zone" ] || return 1
    printf '%s' "$zone"
}

# The console keyboard the live image was started with, if it was started with
# one. The Arch image records it in root's shell history as the loadkeys command
# that set it, which is the only place it can be read back from.
live_keymap() {
    grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ' || true
}

# ─── Values that are worked out rather than asked for ────────────────────────
#
# Each is a variable the user may set, and each falls back to something this
# machine can answer for itself. Doing it here rather than in one stage means
# every stage sees the same answer, however it was arrived at.
#
# `auto` and `none` are the two words the lists in installer.yaml share, and
# neither ever reaches a task. They are not the same test: auto is a value
# still to be found, none is the value itself — the empty answer said out loud.

is_auto() { [ -z "$1" ] || [ "$1" = "auto" ]; }
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# What each of those lists comes to when it is left on auto. Named rather than
# inlined because the question page shows the same answer beside the auto row,
# and the two must never be able to disagree.
auto_keymap() {
    local keymap
    keymap="$(language_keymap "$ARCH_OS_LOCALE_LANG")"
    : "${keymap:=$(live_keymap)}"
    printf '%s' "${keymap:-us}"
}

auto_layout() {
    local layout
    layout="$(language_layout "$ARCH_OS_LOCALE_LANG")"
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
    font="$(language_font "$ARCH_OS_LOCALE_LANG")"
    printf '%s' "${font:-none}"
}

auto_country() {
    local country
    country="$(language_country "$ARCH_OS_LOCALE_LANG")"
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

# Logging in automatically follows disk encryption: the disk is already unlocked
# by a password at boot, so a second password at the login screen protects
# nothing that the first one did not — and without encryption the login screen is
# the only thing standing there.
auto_autologin() { printf '%s' "${ARCH_OS_ENCRYPTION_ENABLED:-false}"; }

# part_of names a partition of a disk. Devices whose name ends in a digit —
# nvme0n1, mmcblk0, loop0 — put a p between the disk and the number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

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

# ─── The console keyboard, in force ──────────────────────────────────────────

# Loading the keyboard on the machine the installer is running on, which is what
# `apply:` calls the moment the language or the keyboard itself is answered:
# until this has run, every answer after it is typed on a layout nobody chose,
# and on a German keyboard read as an American one a password is not the
# password.
load_console_keyboard() {
    # DEBUG runs on somebody's own machine, where the console keyboard is not
    # this installer's to touch.
    [ "$DEBUG" = "true" ] && return 0
    loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
}

# ─── Secure Boot ─────────────────────────────────────────────────────────────

# The same rule the secure-boot task is gated by in its own yaml, in the form
# the two units that only partly depend on it need: the boot loader and the
# initial ram disk are built differently for a signed boot chain, but both run
# either way.
#
# Whether this installation gets Secure Boot, which always comes as a package
# with a Unified Kernel Image. Both are tied to disk encryption on systemd-boot,
# for three reasons:
#   - Without disk encryption, Secure Boot guards a boot chain whose data an
#     attacker simply reads off the drive instead. The two only add up together.
#   - A UKI holds kernel, initramfs and command line in one signed binary.
#     Signing only kernel and boot loader would leave the initramfs on the
#     unencrypted EFI partition forgeable — and a forged initramfs collects the
#     passphrase, which is the very attack this is supposed to stop.
#   - GRUB is left out on purpose: its EFI binary is generated by grub-install,
#     so it would need a re-run plus re-signing after every update, and no hook
#     does that.
secure_boot_wanted() {
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_BOOTLOADER" = "systemd" ]
}

# Whether the firmware is in setup mode — the only state in which our own keys
# may be enrolled. "Secure Boot disabled" is not the same thing: the vendor keys
# are usually still in place, and clearing them is a manual step in the UEFI.
# Read from the UEFI variable rather than parsed out of `sbctl status`, whose
# output is meant for humans: the first four bytes are attributes, the fifth
# holds the value.
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

# ─── The locales to generate ─────────────────────────────────────────────────

# Every line of /etc/locale.gen belonging to the chosen language, uncommented,
# plus English as a fallback — worked out from the one answer rather than asked
# for as a second question nobody could answer usefully.
locale_gen_lines() {
    sed "/^#${ARCH_OS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "^${ARCH_OS_LOCALE_LANG}" || true
    echo 'en_US.UTF-8 UTF-8'
}

# ─── Installing into the new system ──────────────────────────────────────────

# Package installs are retried, because the one thing that reliably goes wrong
# during an installation is the network, and losing twenty minutes of work to a
# mirror that blinked would be absurd.
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

# Building from the AUR needs a normal user who may use sudo without a password,
# which is granted for exactly the length of the build and taken back after —
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

# ─── The first-login script ──────────────────────────────────────────────────

# A few desktop settings can only be applied by the user's own session, because
# they live in that session's settings database and there is no session yet.
# Stages append lines here; the last stage turns whatever collected into a
# script that runs once, at the first login, and then removes itself.
FIRST_LOGIN="${MNT}/home/${ARCH_OS_USERNAME}/.first-login"

on_first_login() { cat >>"$FIRST_LOGIN"; }

# ─── Closing the target again ────────────────────────────────────────────────

# Everything the installation mounted, taken back down in the right order. Used
# by the task that only unmounts, by the one that restarts, and by the way out
# below, so none of them can ever do it differently.
unmount_target() {
    swapoff -a || true
    umount -A -R "$MNT"
    [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot
    echo "unmounted"
}

# ─── Leaving ─────────────────────────────────────────────────────────────────

# The two ways out of the installer — see `leave:` in installer.yaml. They are
# not tasks: nothing follows them, and the interface is asking what to do with
# the machine rather than running a step.
#
# Whatever the installation had mounted is closed first, so a machine restarted
# halfway through a run does not take a half-written file system down with it.
# Nothing mounted is not an error: the question is as likely to be asked before
# the first task as after the last.
leave_machine() {
    simulating && return 0
    unmount_target || true
    systemctl "$1"
}

restart_machine() { leave_machine reboot; }
shutdown_machine() { leave_machine poweroff; }
