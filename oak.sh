# shellcheck shell=bash
# The one library of Arch OS, loaded in front of every script of every module.
# It defines and exports, and runs nothing while it loads.
# https://github.com/murkl/oak/blob/main/docs/REFERENCE.md

# Under --debug only what reads still runs.
debugging() { [ "$DEBUG" = "true" ]; }

is_root() { [ "$(id -u)" -eq 0 ]; }

# https even after a redirect, and a connect timeout instead of a hang.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# An answer written back into the file Oak reads, in place of an earlier one.
answer() {
    local tmp="${MODULE_CONF}.answer"
    grep -v "^${1}=" "$MODULE_CONF" >"$tmp" 2>/dev/null || : >>"$tmp"
    printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >>"$tmp"
    mv -f "$tmp" "$MODULE_CONF"
}

# The data/ folder beside the task.sh or test.sh that called it.
where() { printf '%s/data' "$(dirname "${BASH_SOURCE[1]}")"; }

# ////////////////////////////////////////////////////////////////////////////
# THE RELEASE
# ////////////////////////////////////////////////////////////////////////////

REPO="murkl/arch-os"

# The folder oak.sh and oak.yaml lie in.
product_dir() { dirname "${BASH_SOURCE[0]}"; }

# The release this program is: what a module fetches is what was tested with it.
release_version() { sed -n 's/^version:[[:space:]]*//p' "$(product_dir)/oak.yaml"; }

# The download of that release whose name ends in $1 and its sha256, as two
# words, or nothing where the release is out of reach.
release_asset() {
    local json
    json="$(fetch_url -s --max-time 20 "https://api.github.com/repos/${REPO}/releases/tags/v$(release_version)" || true)"
    printf '%s\n' "$json" | awk -v suffix="$1" '
        function weigh() {
            if (!found && url != "" && substr(url, length(url) - length(suffix) + 1) == suffix) { found = 1; print url, digest }
            url = ""; digest = ""
        }
        /"url": *"[^"]*\/releases\/assets\// { weigh() }
        /"digest": *"sha256:/ { digest = $0; sub(/.*sha256:/, "", digest); sub(/".*/, "", digest) }
        /"browser_download_url": *"/ { url = $0; sub(/.*: *"/, "", url); sub(/".*/, "", url) }
        END { weigh() }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE NETWORK
# ////////////////////////////////////////////////////////////////////////////

# Real HTTPS rather than a ping, which a captive portal answers too. Simulated,
# it is online, so screenshots come out the same on every desk.
check_online() {
    debugging && return 0
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

# The wireless card's station, or nothing. iwd is started only on the live image.
# iwctl colours its table, so the colours come off before a column is read, and
# the match is remembered rather than exited on: a closed pipe fails pipefail.
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
# without an agent. Some cards take a wrong passphrase silently; no address is
# the tell.
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

# Simulated, an address all the same. Oak keeps the log beside the answer file.
share_log() {
    local url
    if debugging; then
        answer ARCH_OS_LOG_URL "${PASTE}/demo"
        return 0
    fi
    url="$(paste_online <"${MODULE_CONF%.conf}.log")"
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

# The btrfs layout, subvolume and mount point - see docs/REFERENCE.md.
export BTRFS_OPTS="defaults,noatime,compress=zstd"

btrfs_subvolumes() {
    printf '%s\t%s\n' \
        @ / \
        @home /home \
        @snapshots /.snapshots \
        @log /var/log \
        @cache /var/cache \
        @tmp /var/tmp \
        @libvirt /var/lib/libvirt/images
}

# Every file sbctl keeps is signed, and there is one. `sbctl verify` answers 0
# whatever it found, so its list is read.
boot_chain_signed() {
    local files
    files="$(arch-chroot "$1" sbctl list-files --json)" || return 1
    if ! grep -q '"is_signed": true' <<<"$files"; then
        echo "sbctl keeps no signed file" >&2
        return 1
    fi
    if grep -q '"is_signed": false' <<<"$files"; then
        echo "sbctl keeps files that are not signed: ${files}" >&2
        return 1
    fi
}

# A shell inside the system, on the terminal Oak hands over. HOME, because a
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
# both fail. Why not envsubst: docs/REFERENCE.md
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

# Keyboard, font and time zone do not follow from the shape of a locale - de_CH
# is not de - so they are looked up in the Installer's data/.
installer_data() { printf '%s/modules/installer/data' "$(product_dir)"; }

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
vconsole_font() { resolved "$ARCH_OS_VCONSOLE_FONT" auto_font; }
desktop_layout() { resolved "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" auto_layout; }
desktop_variant() { not_none "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT"; }
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

# The images the firmware starts - a check against the other two checks nothing.
boot_images() {
    if secure_boot_wanted; then
        printf '/boot/EFI/Linux/arch-%s.efi\n/boot/EFI/Linux/arch-%s-fallback.efi\n' "$KERNEL" "$KERNEL"
    else
        printf '/boot/initramfs-%s.img\n/boot/initramfs-%s-fallback.img\n' "$KERNEL" "$KERNEL"
    fi
}

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
# file under /etc/pacman.d named by one line. Named outright: a glob matching
# nothing stops pacman.
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

# The account's home in the new system, as seen from out here.
user_home() { printf '%s/home/%s' "$MNT" "$ARCH_OS_USERNAME"; }

# The new home given back to its account: what root wrote is root's until then.
own_home() {
    arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
}

# Settings only a session can take: tasks append lines here, and first-login
# turns them into a script that runs once.
on_first_login() { cat >>"$(user_home)/.first-login"; }

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

# Everything under /mnt taken down. Whatever still holds it is logged and
# killed, and a second failure is loud. -R, not -A: the top level is a second
# mount of the same disk.
unmount_target() {
    mountpoint -q "$MNT" || return 0
    umount -R "$MNT" && return 0

    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel needs a moment to actually let go of the files

    umount -R "$MNT"
}

# ////////////////////////////////////////////////////////////////////////////
# WRITING | The image Create boot medium puts on a device
# ////////////////////////////////////////////////////////////////////////////

# The image, named after the version: a machine that has it needs no release.
image() { printf '%s/arch-os-%s-x86_64.iso' "$ARCH_OS_DOWNLOAD_DIR" "$(release_version)"; }

# The checksum beside it, as `sha256sum -c` reads it.
checksum() { printf '%s.sha256' "$(image)"; }

# Root for one command, only where it writes: a root process would leave two
# gigabytes only root can delete. The password goes to sudo on stdin; -k asks
# every time, -p '' keeps the prompt out of the log, -n never asks.
as_root() {
    if is_root; then
        "$@"
    elif [ "$ARCH_OS_IMAGE_SUDO" = "true" ]; then
        printf '%s\n' "$ARCH_OS_IMAGE_PASSWORD" | sudo -S -k -p '' -- "$@"
    else
        sudo -n -- "$@"
    fi
}

# Something of the running system on that disk: swap, or a mount anywhere but
# where a stick is put.
in_system_use() {
    lsblk -nro MOUNTPOINTS "$1" | awk '
        { n = split($0, mounts, /\\x0a/) }
        { for (i = 1; i <= n; i++) if (mounts[i] != "" && mounts[i] !~ /^\/(run\/media|media|mnt)(\/|$)/) found = 1 }
        END { exit !found }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE YAML | Functions a declaration calls as name(), named after the key
# ////////////////////////////////////////////////////////////////////////////

# The wordmark the interface comes up out of, the eyebrow over the blank line.
logo_arch_os() {
    cat <<'EOF'
Arch Linux

 █████  ██████   ██████ ██   ██      ██████  ███████
██   ██ ██   ██ ██      ██   ██     ██    ██ ██
███████ ██████  ██      ███████     ██    ██ ███████
██   ██ ██   ██ ██      ██   ██     ██    ██      ██
██   ██ ██   ██  ██████ ██   ██      ██████  ███████
EOF
}

# The Arch Linux mark beside the words over every module's menu.
icon_arch_linux() {
    cat <<'EOF'
    ▄█▄
   ▄███▄
  ███▀███
▄██▀   ▀██▄
EOF
}

# A list may print a value and the text it is chosen by, with a tab between.

# Whole disks, by size and model.
options_disks() {
    lsblk -dn -o PATH,TYPE,SIZE,MODEL | awk -v live="$(live_disk)" '
        $2 != "disk" || $1 == live || $1 ~ /^\/dev\/zram/ { next }
        { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

options_keymaps() { localectl list-keymaps; }

# The networks in range, strongest first. iwctl returns as soon as a scan has
# started, so the list is read once the card says it is done. An SSID may hold
# spaces, so only two or more separate columns. The connected one, marked ">",
# is still a choice.
options_wifi_networks() {
    local device state
    if debugging; then
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

# ─── The Installer ──────────────────────────────────────────────────────────

value_virtual_machine() {
    if systemd-detect-virt -q; then echo true; else echo false; fi
}

# Loaded the moment it is answered, so what is typed next is typed on it.
apply_vconsole_keymap() {
    debugging && return 0
    loadkeys "$(vconsole_keymap)"
}

# Every UTF-8 locale glibc supports, without @-variants. SUPPORTED rather than
# locale.gen, which cloud-init and hand edits rewrite.
options_locales() {
    sed -n 's/^\([a-z]\{2,3\}\(_[A-Z]\{2\}\)\{0,1\}\)\(\.UTF-8\)\{0,1\} UTF-8$/\1/p' /usr/share/i18n/SUPPORTED | sort -u
}

# The language the interface was set to, as the locale of its own country, read
# from Oak's file beside the answers: de reads de_DE. Otherwise not Afar, the
# first row, but the one locale generated either way.
prefill_locale() {
    local conf lang=""
    conf="$(dirname "$MODULE_CONF")/oak.conf"
    [ ! -f "$conf" ] || lang="$(sed -n "s/^OAK_LANG='\([a-z]\{2,3\}\)'.*/\1/p" "$conf")"
    if [ -n "$lang" ] && grep -q "^${lang}_${lang^^}\(\.UTF-8\)\{0,1\} UTF-8$" /usr/share/i18n/SUPPORTED; then
        printf '%s_%s' "$lang" "${lang^^}"
        return 0
    fi
    printf 'en_US'
}

options_vconsole_keymaps() {
    printf 'auto\tauto — %s\n' "$(auto_keymap)"
    options_keymaps
}

options_fonts() {
    printf 'auto\tauto — %s\n' "$(auto_font)"
    echo none
    find /usr/share/kbd/consolefonts -name '*.psf*' -printf '%f\n' 2>/dev/null |
        sed 's/\.psfu\?\(\.gz\)\?$//' | sort -u
}

options_timezones() { timedatectl list-timezones; }

# The zone of the chosen country, and UTC rather than Africa/Abidjan for none.
prefill_timezone() {
    local locale="${ARCH_OS_LOCALE_LANG%%.*}" territory="" zone
    [[ $locale == *_* ]] && territory="${locale#*_}"
    zone="$(country_field 3 "$territory")"
    printf '%s' "${zone:-UTC}"
}

options_countries() {
    printf 'auto\tauto — %s\n' "$(auto_country)"
    echo none
    # A "-" marks a country Arch has no mirror in.
    awk -F'\t' '!/^#/ && $2 != "-" { print $2 }' "$(installer_data)/countries"
}

# The Arch ISO ships no xkeyboard-config, and then data/ answers.
options_layouts() {
    printf 'auto\tauto — %s\n' "$(auto_layout)"

    local layouts
    layouts="$(localectl list-x11-keymap-layouts 2>/dev/null || true)"
    if [ -n "$layouts" ]; then
        echo "$layouts"
        return 0
    fi
    grep -v '^#' "$(installer_data)/x11-layouts"
}

options_variants() {
    local layout variants
    layout="$(desktop_layout)"
    [ -n "$layout" ] || return 0

    echo none

    variants="$(localectl list-x11-keymap-variants "$layout" 2>/dev/null || true)"
    if [ -n "$variants" ]; then
        echo "$variants"
        return 0
    fi
    # A layout without variants has no line there.
    { grep "^${layout} " "$(installer_data)/x11-variants" || true; } | cut -d' ' -f2- | tr ' ' '\n'
}

# ─── The Recovery ───────────────────────────────────────────────────────────

# The keyboard the live image was started with: the Arch image records it only as
# a loadkeys line in root's history.
prefill_live_keymap() {
    local keymap
    keymap="$({ grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ')"
    printf '%s' "${keymap:-us}"
}

# Loaded the moment it is answered.
apply_recovery_keymap() {
    debugging && return 0
    loadkeys "$ARCH_OS_RECOVERY_KEYMAP"
}

# --test-passphrase opens nothing, it only asks the keyslots.
check_disk_password() {
    debugging && return 0
    printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open --test-passphrase "$(target_partition)"
}

# A LUKS header is readable without the password.
value_disk_encrypted() {
    [ "$(fstype "$(target_partition)")" = "crypto_LUKS" ] && echo true || echo false
}

# ─── Create boot medium ─────────────────────────────────────────────────────

# The session's download folder, or the one every desktop falls back to.
# https://specifications.freedesktop.org/basedir-spec/latest/
prefill_download_dir() {
    [ -n "${XDG_DOWNLOAD_DIR:-}" ] && {
        printf '%s' "$XDG_DOWNLOAD_DIR"
        return 0
    }
    printf '%s/Downloads' "${HOME:-$(dirname "$MODULE_CONF")}"
}

# The USB disks, without the ones the running system is on: a system can live
# on a USB disk too.
options_devices() {
    local path shown
    while IFS=$'\t' read -r path shown; do
        in_system_use "$path" && continue
        printf '%s\t%s\n' "$path" "$shown"
    done < <(lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print path "\t" path "  " $0 }')
}

# Whether the write needs a password. -k ignores one sudo remembers now and will
# have forgotten by the write.
value_needs_password() {
    if is_root || sudo -nk true 2>/dev/null; then echo false; else echo true; fi
}

# The password tried on sudo with a command that does nothing.
check_sudo_password() {
    debugging && return 0
    as_root true
}
