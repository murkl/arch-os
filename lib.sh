# shellcheck shell=bash
# The one library of Arch OS, loaded in front of every script of every module.
# It defines and exports, and runs nothing while it loads: runtime/README.md

# Under --dry-run only what reads still runs.
dry_run() { [ "$DRY_RUN" = "true" ]; }

is_root() { [ "$(id -u)" -eq 0 ]; }

# https even after a redirect, and a connect timeout instead of a hang.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# An answer written back into the answer file, in place of an earlier one.
answer() {
    local tmp="${MODULE_CONF}.answer"
    grep -v "^${1}=" "$MODULE_CONF" >"$tmp" 2>/dev/null || : >>"$tmp"
    printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >>"$tmp"
    mv -f "$tmp" "$MODULE_CONF"
}

# The data/ folder beside the task.sh or test.sh that called it.
where() { printf '%s/data' "$(dirname "${BASH_SOURCE[1]}")"; }

# ////////////////////////////////////////////////////////////////////////////
# THE ERRORS
# ////////////////////////////////////////////////////////////////////////////

# What a script stops itself with where it cannot go on, put into words under
# errors: in each module.yaml. A task's or action's own statuses start at 10.
export EXIT_OFFLINE=3     # the internet is out of reach
export EXIT_UNREACHABLE=4 # the internet works, the release page does not answer
export EXIT_AUR=5         # the internet works, the AUR does not answer

# ////////////////////////////////////////////////////////////////////////////
# THE RELEASE
# ////////////////////////////////////////////////////////////////////////////

REPO="murkl/arch-os"

# The folder lib.sh and the modules lie in.
product_dir() { dirname "${BASH_SOURCE[0]}"; }

# Releases as GitHub describes them: tags/v1.2.3 for one, nothing for the
# newest hundred. Fails where it is out of reach.
release_json() {
    local path="releases?per_page=100"
    [ -z "${1:-}" ] || path="releases/$1"
    fetch_url -sS --max-time 20 "https://api.github.com/repos/${REPO}/${path}"
}

# Every download in the releases' JSON on stdin whose name ends in $1, with its
# sha256, a line each. One field to a line, however GitHub lays the JSON out.
asset_in() {
    tr ',' '\n' | awk -v suffix="$1" '
        function weigh() {
            if (url != "" && substr(url, length(url) - length(suffix) + 1) == suffix) print url, digest
            url = ""; digest = ""
        }
        /"url": *"[^"]*\/releases\/assets\// { weigh() }
        /"digest": *"sha256:/ { digest = $0; sub(/.*sha256:/, "", digest); sub(/".*/, "", digest) }
        /"browser_download_url": *"/ { url = $0; sub(/.*: *"/, "", url); sub(/".*/, "", url) }
        END { weigh() }'
}

# Whether version $1 comes after $2, as semantic versioning orders them: a
# pre-release before its release, 2.1.0-dev before 2.1.0.
newer() {
    local release1="${1%%-*}" release2="${2%%-*}"
    if [ "$release1" != "$release2" ]; then
        [ "$(printf '%s\n%s\n' "$release1" "$release2" | sort -V | tail -n1)" = "$release1" ]
    elif [ "$1" = "$release1" ]; then
        [ "$2" != "$release2" ]
    else
        [ "$2" != "$release2" ] && [ "$1" != "$2" ] &&
            [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
    fi
}

# ////////////////////////////////////////////////////////////////////////////
# THE NETWORK
# ////////////////////////////////////////////////////////////////////////////

# Real HTTPS rather than a ping, which a captive portal answers too. Simulated,
# it is online, so screenshots come out the same on every desk.
check_online() {
    dry_run && return 0
    fetch_url -sI --connect-timeout 5 --max-time 10 https://archlinux.org >/dev/null
}

has_wifi_card() { compgen -G '/sys/class/ieee80211/*' >/dev/null; }

# Online, and not over the air: the default route leaves by an interface with no
# wireless card. The address is reserved for documentation; looking up its route
# sends nothing.
online_by_cable() {
    local route device
    check_online || return 1
    route="$(ip -o route get 192.0.2.1)" || return 1
    device="$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1) }' <<<"$route")"
    [ -n "$device" ] && [ ! -e "/sys/class/net/${device}/phy80211" ]
}

# The Wi-Fi card's station, or nothing; iwd starts only on the live image. The
# match is remembered rather than exited on, since a closed pipe fails pipefail.
wifi_station() {
    local station=""
    has_wifi_card || return 0
    if on_live_image && ! systemctl is-active -q iwd; then
        systemctl start iwd
    fi
    for _ in $(seq 10); do
        station="$(iwctl device list |
            sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
            awk '!found && $NF == "station" { print $1; found = 1 }')"
        [ -n "$station" ] && break
        sleep 0.5 # a daemon started just now has not found the card yet
    done
    printf '%s' "$station"
}

# Joined is not yet online: the address comes a few seconds later.
wifi_online() {
    for _ in $(seq 6); do
        check_online && return 0
        sleep 2
    done
    return 1
}

# Without --dont-ask, iwctl asks for a passphrase on the interface's terminal.
join_wifi() {
    iwctl --dont-ask station "$(wifi_station)" connect "$ARCH_OS_WIFI_SSID"
    wifi_online || true
}

# The one place a secret reaches a command line: iwctl takes it no other way
# without an agent. No address is the tell for a wrong passphrase.
join_wifi_with_passphrase() {
    iwctl --passphrase "$ARCH_OS_WIFI_PASSPHRASE" station "$(wifi_station)" connect "$ARCH_OS_WIFI_SSID"
    wifi_online
}

# ////////////////////////////////////////////////////////////////////////////
# THE SHARING
# ////////////////////////////////////////////////////////////////////////////

# No account and no key: a POST in, the address it lives at out.
export PASTE="https://paste.rs"

# Retried, since paste.rs answers a busy moment with an error, and -S puts the
# status it answered with on the page that says it failed.
paste_online() {
    fetch_url -sS --max-time 30 --retry 3 --retry-delay 2 --data-binary @- "${PASTE}/" | tr -d '[:space:]'
}

# Simulated, an address all the same. The log lies beside the answer file.
share_log() {
    local url
    if dry_run; then
        answer ARCH_OS_LOG_URL "${PASTE}/demo"
        return 0
    fi
    url="$(paste_online <"$MODULE_LOG")"
    [ -n "$url" ] || return 1
    answer ARCH_OS_LOG_URL "$url"
}

# ////////////////////////////////////////////////////////////////////////////
# THE LIVE IMAGE
# ////////////////////////////////////////////////////////////////////////////

# Either marker is enough: what the image mounts, or what it was booted with.
on_live_image() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

# Arch on top: an image built the same way by somebody else is another system.
on_arch_live_image() {
    on_live_image && grep -qs '^ID=arch$' /etc/os-release
}

# The disk the live image runs from, also through Ventoy. No module writes to it.
live_disk() {
    lsblk -no PKNAME,MOUNTPOINT |
        awk '!found && $1 != "" && $2 ~ /^\/run\/archiso/ { print "/dev/" $1; found = 1 }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE SYSTEM ON THE DISK
# ////////////////////////////////////////////////////////////////////////////

# Where the Installer builds the system and the Recovery opens it.
export MNT=/mnt

# The one kernel Arch OS installs, and so the one the Recovery puts back.
export KERNEL=linux-zen

# The partitions the Installer lays out and the Recovery finds again. nvme0n1
# gets a p.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}
boot_partition() { part_of "$1" 1; }
system_partition() { part_of "$1" 2; }
recovery_partition() { part_of "$1" 3; }

# The btrfs layout, subvolume and mount point, see docs/REFERENCE.md.
export BTRFS_OPTS="defaults,noatime,compress=zstd:1"

btrfs_subvolumes() {
    printf '%s\t%s\n' \
        @ / \
        @home /home \
        @snapshots /.snapshots \
        @log /var/log \
        @cache /var/cache \
        @tmp /var/tmp
}

# ─── The boot entries ──────────────────────────────────────────────────────
#
# What the Installer writes and the Recovery lays down again, each entry of the
# system tried BOOT_TRIES times before the next: docs/REFERENCE.md#when-the-system-does-not-start

# The templates, kept with the Recovery, which every image carries.
boot_data() { printf '%s/recovery/data/boot' "$(product_dir)"; }

export BOOT_TRIES=3

# The unified images, outside EFI/Linux: the loader would list them there on
# their own, beside the entries that count their tries.
export UKI_DIR=/boot/EFI/arch-os

# The images the firmware starts for kind $1, uki or image, the system's first.
images_of() {
    if [ "$1" = uki ]; then
        printf '%s/arch-%s.efi\n%s/arch-%s-fallback.efi\n' "$UKI_DIR" "$KERNEL" "$UKI_DIR" "$KERNEL"
    else
        printf '/boot/initramfs-%s.img\n/boot/initramfs-%s-fallback.img\n' "$KERNEL" "$KERNEL"
    fi
}

# Text written beside a file and moved over it, so whatever reads it at the
# next start finds the old file or the new one, never half of either.
place() {
    printf '%s\n' "$2" >"${1}.new"
    mv -f "${1}.new" "$1"
}

# mkinitcpio's preset in the system at $1 for kind $2.
boot_preset() {
    local images text
    mapfile -t images < <(images_of "$2")
    text="$(render "$(boot_data)/$2.preset" KERNEL="$KERNEL" DEFAULT="${images[0]}" FALLBACK="${images[1]}")"
    place "$1/etc/mkinitcpio.d/${KERNEL}.preset" "$text"
}

# The system's two entries, the loader's configuration and the unit that gives
# the entries their tries back, in the system at $1 for kind $2 and, for ram
# disks, the command line $3. Each entry is in place before an old name goes.
boot_entries() {
    local root="$1" kind="$2" cmdline="$3" data entries images text file old i
    local -a names=(main main-fallback) titles=("Arch OS" "Arch OS (fallback)") keys=(arch arch-fallback)
    data="$(boot_data)"
    entries="${root}/boot/loader/entries"
    mapfile -t images < <(images_of "$kind")
    mkdir -p "$entries" "${root}/usr/local/lib/arch-os" "${root}/etc/systemd/system"

    for i in 0 1; do
        if [ "$kind" = uki ]; then
            text="$(render "${data}/uki-entry.conf" TITLE="${titles[i]}" SORT_KEY="${keys[i]}" UKI="${images[i]#/boot}")"
        else
            text="$(render "${data}/entry.conf" TITLE="${titles[i]}" SORT_KEY="${keys[i]}" KERNEL="$KERNEL" \
                INITRD="${images[i]#/boot/}" CMDLINE="$cmdline")"
        fi
        file="${entries}/${names[i]}+${BOOT_TRIES}.conf"
        place "$file" "$text"
        for old in "${entries}/${names[i]}.conf" "${entries}/${names[i]}+"*.conf; do
            [ "$old" = "$file" ] || rm -f "$old"
        done
    done

    text="$(render "${data}/loader.conf")"
    place "${root}/boot/loader/loader.conf" "$text"
    text="$(render "${data}/boot-tries.sh")"
    place "${root}/usr/local/lib/arch-os/boot-tries.sh" "$text"
    chmod 755 "${root}/usr/local/lib/arch-os/boot-tries.sh"
    text="$(render "${data}/arch-os-boot-tries.service" TRIES="$BOOT_TRIES")"
    place "${root}/etc/systemd/system/arch-os-boot-tries.service" "$text"
    arch-chroot "$root" systemctl enable arch-os-boot-tries.service
}

# A default an earlier system left in this machine's firmware is started
# however often it fails, so the entries' tries count for nothing past it.
clear_loader_default() {
    [ -e /sys/firmware/efi/efivars/LoaderEntryDefault-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f ] || return 0
    bootctl set-default '' || echo "the firmware's default boot entry could not be cleared" >&2
}

# Everything under /mnt taken down, and whatever still holds it logged and
# killed. Why -R and -M: docs/CONTRIBUTING.md#closing-the-target
unmount_target() {
    mountpoint -q "$MNT" || return 0
    umount -R "$MNT" && return 0

    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel needs a moment to actually let go of the files

    umount -R "$MNT"
}

# Every file sbctl keeps is signed, and there is one. `sbctl verify` answers 0
# whatever it found, so its list is read, however it spaces its JSON.
boot_chain_signed() {
    local files
    files="$(arch-chroot "$1" sbctl list-files --json)" || return 1
    if ! grep -qE '"is_signed": *true' <<<"$files"; then
        echo "sbctl keeps no signed file" >&2
        return 1
    fi
    if grep -qE '"is_signed": *false' <<<"$files"; then
        echo "sbctl keeps files that are not signed: ${files}" >&2
        return 1
    fi
}

# A shell inside the system, on the terminal the runtime hands over. HOME, because a
# service has none; the shell's own exit is whoever typed in it.
open_shell() {
    clear
    echo "You are now inside the system at ${MNT}."
    echo "Leave it again with 'exit'."
    echo
    HOME=/root arch-chroot "$MNT" || true
}

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING | Files a task ships
# ////////////////////////////////////////////////////////////////////////////

# A template from a task's data/ on stdout: {{NAME}} filled from NAME=value,
# every $ left alone. A placeholder nobody filled and a value nothing asks for
# both fail. Why not envsubst: docs/CONTRIBUTING.md#files-a-task-ships
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

    # Left to right and once: a value holding {{ is never read as a placeholder.
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
# INSTALLING | The region, looked up and worked out
# ////////////////////////////////////////////////////////////////////////////

# Keyboard, font and time zone do not follow from the shape of a locale (de_CH
# is not de), so they are looked up in the Installer's data/.
installer_data() { printf '%s/installer/data' "$(product_dir)"; }

# A column of data/languages for a locale: its own row, else its language's.
language_field() {
    awk -v col="$1" -v locale="${2%%.*}" '
        BEGIN { lang = locale; sub(/_.*/, "", lang) }
        /^#/ || NF == 0 { next }
        $1 == locale { hit = $0; exit }
        $1 == lang && fallback == "" { fallback = $0 }
        END { split(hit != "" ? hit : fallback, f); print f[col] }
    ' "$(installer_data)/languages"
}

# A column of data/countries for a territory code; empty for none.
country_field() {
    awk -F'\t' -v col="$1" -v code="$2" 'code != "" && $1 == code { print $col }' "$(installer_data)/countries"
}

# What auto resolves to, also shown beside the auto row of each list.
auto_keymap() {
    local keymap
    keymap="$(language_field 2 "$ARCH_OS_LOCALE_LANG")"
    # Otherwise the keyboard the live image was started with.
    printf '%s' "${keymap:-$(prefill_live_keymap)}"
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

# The country of the time zone rather than of the language: en_US is typed on
# every continent.
auto_country() {
    local territory country
    territory="$(awk -F'\t' -v zone="$ARCH_OS_TIMEZONE" \
        '!/^#/ && zone != "" && $3 == zone { print $1 }' /usr/share/zoneinfo/zone.tab)"
    country="$(country_field 2 "$territory")"
    [ "$country" = "-" ] && country="" # a country Arch has no mirror in
    printf '%s' "${country:-none}"
}

# none is answered, and stands for nothing set.
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# An answer as the new system is set to it, auto worked out by the function
# named second.
resolved() {
    local value="$1"
    if [ -z "$value" ] || [ "$value" = "auto" ]; then
        value="$("$2")"
    fi
    not_none "$value"
}

vconsole_keymap() { resolved "$ARCH_OS_VCONSOLE_KEYMAP" auto_keymap; }
desktop_layout() { resolved "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" auto_layout; }
mirror_country() { resolved "$ARCH_OS_REFLECTOR_COUNTRY" auto_country; }

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING | The machine and its boot chain
# ////////////////////////////////////////////////////////////////////////////

# The processor's microcode package, or nothing.
microcode() {
    if grep -q GenuineIntel /proc/cpuinfo; then
        echo intel-ucode
    elif grep -q AuthenticAMD /proc/cpuinfo; then
        echo amd-ucode
    fi
}

# Each graphics card as vendor, a tab and the PCI device ID, off sysfs. A
# virtual machine's own adapter is none of the three.
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

# Secure Boot always means a unified kernel image.
# https://wiki.archlinux.org/title/Unified_kernel_image
secure_boot_wanted() {
    [ "$ARCH_OS_SECURE_BOOT_ENABLED" = "true" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]
}

# The kind of image the Installer builds.
boot_kind() { if secure_boot_wanted; then echo uki; else echo image; fi; }

# The images the firmware starts: a check against the other two checks nothing.
boot_images() { images_of "$(boot_kind)"; }

# The Recovery image: on the Arch OS ISO already, else fetched into /tmp. How it
# boots: docs/REFERENCE.md
recovery_image() {
    if [ -d /opt/arch-os-recovery ]; then
        echo /opt/arch-os-recovery
    else
        echo /tmp/arch-os-recovery
    fi
}

# Where it lands on the EFI partition, listed by systemd-boot on its own.
export RECOVERY_EFI=/boot/EFI/Linux/arch-os-recovery.efi

# Its partition: twice what its image takes, so an update has room to grow.
export RECOVERY_MIB=1024

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING | Into the new system
# ////////////////////////////////////////////////////////////////////////////

# Retried, since the network is what goes wrong. pacman's own timeout turns a
# mirror gone away into a retry against the next.
export RETRIES=5
export RETRY_WAIT=10

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
    check_online || exit "$EXIT_OFFLINE"
    return 1
}

# A sudo rule from stdin as a drop-in, taken back out where visudo refuses it:
# one unreadable file there refuses every sudo. https://wiki.archlinux.org/title/Sudo
sudoers_rule() {
    local file="${MNT}/etc/sudoers.d/${1}"
    mkdir -p "${MNT}/etc/sudoers.d"
    cat >"$file"
    chmod 0440 "$file"
    arch-chroot "$MNT" visudo -cqf "/etc/sudoers.d/${1}" && return 0
    rm -f "$file"
    echo "the sudo rule ${1} was rejected and was removed again" >&2
    return 1
}

# pacman reads no drop-in directory but follows an Include, so each setting is a
# file under /etc/pacman.d named outright: a glob matching nothing stops pacman.
# https://man.archlinux.org/man/pacman.conf.5
pacman_include() {
    local file
    file="/etc/pacman.d/$(basename "$1")"
    render "$1" >"${MNT}${file}"
    grep -qxF "Include = ${file}" "${MNT}/etc/pacman.conf" ||
        echo "Include = ${file}" >>"${MNT}/etc/pacman.conf"
}

# How often a build is tried, and one attempt's limit: one that hits it was
# stuck.
AUR_RETRIES=3
AUR_TIMEOUT=2700

# A package from the AUR, built as the account with passwordless sudo granted
# for the build alone. One compile job per GiB of memory, see docs/REFERENCE.md.
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
    # Added to the PKGBUILD's options, so one that says !lto keeps it.
    build="${build} && printf '\noptions+=(\"!debug\")\n' >>PKGBUILD"
    # make and cargo read their own variables. cargo's caches stay in the build
    # directory and go with it, rather than a hundred megabytes in the new home.
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

    # Taken back before anything that can fail, or passwordless sudo stays.
    rm -f "${MNT}/etc/sudoers.d/99-aur-build"
    rm -rf "${MNT}${dir}" || echo "the build directory ${dir} could not be removed" >&2

    [ "$status" -eq 0 ] && return 0
    echo "building ${repo} from the AUR did not finish" >&2
    check_online || exit "$EXIT_OFFLINE"
    fetch_url -sI --max-time 20 https://aur.archlinux.org >/dev/null || exit "$EXIT_AUR"
    return "$status"
}

# A command inside the new system as the account, which makepkg insists on.
as_user() {
    arch-chroot "$MNT" /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "$1"
}

# The chosen browser's desktop entry, not its package's name for two of them.
browser_entry() {
    case "$ARCH_OS_BROWSER" in
    epiphany) echo org.gnome.Epiphany.desktop ;;
    vivaldi) echo vivaldi-stable.desktop ;;
    *) echo "${ARCH_OS_BROWSER}.desktop" ;;
    esac
}

# The account's home in the new system, as seen from out here.
user_home() { printf '%s/home/%s' "$MNT" "$ARCH_OS_USERNAME"; }

# The new home given back to its account: what root wrote is root's until then.
own_home() {
    arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
}

# Asked of the new system: an absolute link in its /usr/bin points into the
# live system from out here.
has_command() { arch-chroot "$MNT" test -x "/usr/bin/${1}"; }

# sysctl says nothing about a key it does not have, so each is looked for.
sysctl_keys_exist() {
    local keys key
    keys="$(sed -n 's/^[[:space:]]*\([a-z][a-z0-9._-]*\)[[:space:]]*=.*/\1/p' "$1")"

    # No keys at all would pass without having looked.
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
# REPAIRING | The system the Recovery opens
# ////////////////////////////////////////////////////////////////////////////

# The name of the unlocked disk under /dev/mapper.
export CRYPT=recovery

# The btrfs top level, where a rollback happens. Outside MNT, so it is in no
# chroot and outlives an unmount there.
export BTRFS_TOP=/run/arch-os-recovery

# The system partition, while it is LUKS or a btrfs labelled BTRFS. Raw output
# keeps an empty column a column.
target_partition() {
    local part
    part="$(system_partition "$ARCH_OS_RECOVERY_DISK")"
    lsblk -dnro FSTYPE,LABEL "$part" 2>/dev/null | awk -F'[ ]' -v part="$part" '
        $1 == "crypto_LUKS" || ($1 == "btrfs" && $2 == "BTRFS") { print part }'
}

# The unlocked mapper where the disk is encrypted, the partition where it is not.
target_device() {
    if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
        printf '/dev/mapper/%s' "$CRYPT"
    else
        target_partition
    fi
}

# The device's own file system: without -d an unlocked LUKS partition answers
# btrfs, from the layer on top.
fstype() { lsblk -dno FSTYPE "$1" 2>/dev/null || true; }

# The system mounted by the layout the Installer lays out: @ first, then /boot
# from partition 1. Not by its fstab, which may be what broke.
mount_target() {
    local device subvolume path
    device="$(target_device)"
    while IFS=$'\t' read -r subvolume path; do
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" "$device" "${MNT}${path%/}"
    done < <(btrfs_subvolumes)
    mount --mkdir -t vfat "$(boot_partition "$ARCH_OS_RECOVERY_DISK")" "${MNT}/boot"
}

# The system closed for good, whatever an earlier run left open: a system still
# standing cannot be locked either.
close_target() {
    swapoff -a || true
    sync
    unmount_target
    if mountpoint -q "$BTRFS_TOP"; then
        umount -R "$BTRFS_TOP"
    fi
    if [ -e "/dev/mapper/${CRYPT}" ]; then
        cryptsetup close "$CRYPT"
    fi
}

# ////////////////////////////////////////////////////////////////////////////
# REPAIRING | The Recovery, updated
# ////////////////////////////////////////////////////////////////////////////

# Started from its partition on the disk it repairs: the UUID its command line
# names is that disk's third partition.
on_recovery_partition() {
    local uuid
    uuid="$(sed -n 's/.*archisodevice=UUID=\([^ ]*\).*/\1/p' /proc/cmdline)"
    [ -n "$uuid" ] && [ -n "$ARCH_OS_RECOVERY_DISK" ] &&
        [ "$(blkid -p -s UUID -o value "$(recovery_partition "$ARCH_OS_RECOVERY_DISK")" 2>/dev/null)" = "$uuid" ]
}

# Whether the disk's Recovery starts: the loader lists a boot image naming the
# UUID its partition has, which an update cut short leaves apart.
recovery_starts() {
    local uuid esp mnt listed="" status=0
    uuid="$(blkid -p -s UUID -o value "$(recovery_partition "$ARCH_OS_RECOVERY_DISK")")" || return 1
    esp="$(boot_partition "$ARCH_OS_RECOVERY_DISK")"
    mnt="$({ findmnt -nro TARGET -S "$esp" || true; } | awk '!found { print; found = 1 }')"
    if [ -n "$mnt" ]; then
        listed="$(bootctl --esp-path="$mnt" list --json=short)" || status=$?
    else
        mnt="$(mktemp -d)"
        if mount -o ro -t vfat "$esp" "$mnt"; then
            listed="$(bootctl --esp-path="$mnt" list --json=short)" || status=$?
            umount "$mnt"
        else
            status=1
        fi
        rmdir "$mnt"
    fi
    [ "$status" -eq 0 ] && [ -n "$uuid" ] && grep -qE "archisodevice=UUID=${uuid}( |\")" <<<"$listed"
}

# The newest Recovery of this release series in the releases' JSON on stdin, as
# version, download and sha256, without pre-releases. A new major version may
# lay a system out differently, which this series' Recovery would not repair.
newest_recovery() {
    local series url digest version newest=""
    series="$(printf "%s" "$MODULE_VERSION" | cut -d. -f1)"
    while read -r url digest; do
        version="${url##*/arch-os-}"
        version="${version%-recovery-x86_64.tar}"
        [[ $version =~ ^${series}\.[0-9]+\.[0-9]+$ ]] && [ -n "$digest" ] || continue
        if [ -z "$newest" ] || newer "$version" "${newest%% *}"; then
            newest="${version} ${url} ${digest}"
        fi
    done < <(asset_in -recovery-x86_64.tar)
    [ -z "$newest" ] || printf '%s\n' "$newest"
}

# What an update installs, as newest_recovery puts it, or nothing: on its own
# partition the newest where it is newer than this one, from anywhere else the
# newest where the disk's own does not start.
recovery_update() {
    local found
    found="$(newest_recovery)"
    [ -n "$found" ] || return 0
    if on_recovery_partition; then
        newer "${found%% *}" "${MODULE_VERSION}" || return 0
    elif recovery_starts; then
        return 0
    fi
    printf '%s\n' "$found"
}

# ////////////////////////////////////////////////////////////////////////////
# THE YAML | Functions a declaration calls as name(), named after the key
# ////////////////////////////////////////////////////////////////////////////

# A list may print a value and the text it is chosen by, with a tab between.

# Whole disks, by size and model.
options_disks() {
    lsblk -dn -o PATH,TYPE,SIZE,MODEL | awk -v live="$(live_disk)" '
        $2 != "disk" || $1 == live || $1 ~ /^\/dev\/zram/ { next }
        { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

options_keymaps() { localectl list-keymaps; }

# The networks in range, strongest first, once the card says its scan is done.
# Columns split on two spaces, since an SSID may hold one.
options_wifi_networks() {
    local device state
    if dry_run; then
        printf '%s\n' Home "Coffee Bar Free"
        return 0
    fi

    device="$(wifi_station)"
    iwctl station "$device" scan || true
    for _ in $(seq 20); do
        sleep 0.5
        state="$(iwctl station "$device" show | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//')"
        grep -qE '^[[:space:]]*Scanning[[:space:]]+no([[:space:]]|$)' <<<"$state" && break
    done

    iwctl station "$device" get-networks |
        sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
        awk '
            /^[[:space:]]*-+[[:space:]]*$/ { rules++; next }
            rules < 2 { next }
            {
                line = $0
                sub(/^[[:space:]]*>?[[:space:]]*/, "", line)
                sub(/[[:space:]]+$/, "", line)
                if (line == "") next
                split(line, col, /[[:space:]][[:space:]]+/)
                name = col[1]
                if (name == "" || seen[name]++) next
                print name
            }
        '
}

# The keyboard the live image was started with: the Arch image records it only as
# a loadkeys line in root's history.
prefill_live_keymap() {
    local keymap
    keymap="$({ grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ')"
    printf '%s' "${keymap:-us}"
}

# --test-passphrase opens nothing, it only asks the keyslots.
unlocks() { printf '%s' "$1" | cryptsetup open --test-passphrase "$(target_partition)"; }
