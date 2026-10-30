# shellcheck shell=bash
# Sourced before every module script. Defines and exports, runs nothing on load: runtime/README.md

dry_run() { [ "$DRY_RUN" = "true" ]; }

is_root() { [ "$(id -u)" -eq 0 ]; }

# Treats the named exit codes of the previous command as success: `grep x file || allow 1`.
allow() {
    local status=$?
    for code; do
        if [ "$status" -eq "$code" ]; then return 0; fi
    done
    return "$status"
}

# Every outbound request goes through here. A transfer below 1 KiB/s for a
# minute fails, since a stalled connection stays open without an end.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 10 \
        --speed-limit 1024 --speed-time 60 "$@"
}

# Sets $1 to $2 in the answer file, replacing an earlier value.
answer() {
    local tmp="${MODULE_CONF}.answer"
    grep -v "^${1}=" "$MODULE_CONF" >"$tmp" 2>/dev/null || : >>"$tmp"
    printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >>"$tmp"
    mv -f "$tmp" "$MODULE_CONF"
}

# data/ beside the calling task.sh or test.sh.
where() { printf '%s/data' "$(dirname "${BASH_SOURCE[1]}")"; }

# ////////////////////////////////////////////////////////////////////////////
# THE ERRORS
# ////////////////////////////////////////////////////////////////////////////

# Shared exit codes, described under errors: in each module.yaml. Task and action codes start at 10.
export EXIT_OFFLINE=3
export EXIT_UNREACHABLE=4 # online, GitHub unreachable
export EXIT_AUR=5         # online, AUR unreachable

# ////////////////////////////////////////////////////////////////////////////
# THE RELEASE
# ////////////////////////////////////////////////////////////////////////////

REPO="murkl/arch-os"

product_dir() { dirname "${BASH_SOURCE[0]}"; }

releases_json() { fetch_url -sS --max-time 20 "https://api.github.com/repos/${REPO}/releases?per_page=100"; }

# URL and sha256 of each asset ending in $1, from releases JSON on stdin. Assets
# published before GitHub kept digests leave the sha256 empty.
asset_in() {
    jq -r --arg suffix "$1" '.[] | .assets[]? | select(.browser_download_url | endswith($suffix))
        | "\(.browser_download_url) \(.digest // "" | ltrimstr("sha256:"))"'
}

# Semver order: 2.1.0-dev before 2.1.0.
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

# HTTPS rather than ping, which a captive portal answers too. Online under
# --dry-run, so screenshots stay reproducible.
check_online() {
    dry_run && return 0
    fetch_url -sI --connect-timeout 5 --max-time 10 https://archlinux.org >/dev/null
}

has_wifi_card() { compgen -G '/sys/class/ieee80211/*' >/dev/null; }

# Online through an interface without a wireless card. 192.0.2.1 is a
# documentation address, the route lookup sends nothing.
online_by_cable() {
    local route device
    check_online || return 1
    route="$(ip -o route get 192.0.2.1)" || return 1
    device="$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1) }' <<<"$route")"
    [ -n "$device" ] && [ ! -e "/sys/class/net/${device}/phy80211" ]
}

# The Wi-Fi station, or nothing. awk reads to the end, since a closed pipe fails
# pipefail.
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
        sleep 0.5 # a fresh iwd lists the card only after a moment
    done
    printf '%s' "$station"
}

# DHCP completes a few seconds after joining.
wifi_online() {
    for _ in $(seq 6); do
        check_online && return 0
        sleep 2
    done
    return 1
}

# Without --dont-ask, iwctl prompts for a passphrase on the runtime's terminal.
join_wifi() {
    iwctl --dont-ask station "$(wifi_station)" connect "$ARCH_OS_WIFI_SSID"
    wifi_online || true
}

# The only secret on a command line: without an agent, iwctl takes it no other
# way. A wrong passphrase shows as no address.
join_wifi_with_passphrase() {
    iwctl --passphrase "$ARCH_OS_WIFI_PASSPHRASE" station "$(wifi_station)" connect "$ARCH_OS_WIFI_SSID" || exit 10
    wifi_online || exit 10
}

# ////////////////////////////////////////////////////////////////////////////
# THE SHARING
# ////////////////////////////////////////////////////////////////////////////

# No account or key: POST the text, get its URL back.
export PASTE="https://paste.rs"

# Retried, since paste.rs fails under load. -S puts the HTTP status in the log.
paste_online() {
    fetch_url -sS --max-time 30 --retry 3 --retry-delay 2 --data-binary @- "${PASTE}/" | tr -d '[:space:]'
}

# Offline or paste.rs unavailable, each with its own text.
paste_failed() {
    check_online || exit "$EXIT_OFFLINE"
    exit 10
}

# A demo URL under --dry-run, so the page shows one.
share_log() {
    local url
    if dry_run; then
        answer ARCH_OS_LOG_URL "${PASTE}/demo"
        return 0
    fi
    url="$(paste_online <"$MODULE_LOG")" || url=""
    [ -n "$url" ] || paste_failed
    answer ARCH_OS_LOG_URL "$url"
}

# ////////////////////////////////////////////////////////////////////////////
# THE LIVE IMAGE
# ////////////////////////////////////////////////////////////////////////////

# The archiso mount or the kernel parameter, either suffices.
on_live_image() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

# Another distribution's archiso image is not Arch.
on_arch_live_image() {
    on_live_image && grep -qs '^ID=arch$' /etc/os-release
}

# The disk the live system runs from, also via Ventoy. No module writes to it.
live_disk() {
    lsblk -no PKNAME,MOUNTPOINT |
        awk '!found && $1 != "" && $2 ~ /^\/run\/archiso/ { print "/dev/" $1; found = 1 }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE SYSTEM ON THE DISK
# ////////////////////////////////////////////////////////////////////////////

# Root of the system the Installer builds and the Recovery repairs.
export MNT=/mnt

# The only kernel Arch OS installs, and the one the Recovery restores.
export KERNEL=linux-zen

# Partition $2 of disk $1. A disk name ending in a digit takes a p: nvme0n1p1.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}
boot_partition() { part_of "$1" 1; }
system_partition() { part_of "$1" 2; }
recovery_partition() { part_of "$1" 3; }

# The smallest disk in GiB per profile, as docs/README.md names it. The Installer
# refuses a smaller one, and e2e.sh installs on exactly these.
export CORE_GIB=16
export DESKTOP_GIB=32

# The btrfs layout: docs/REFERENCE.md
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
# Written by the Installer, restored by the Recovery. Each entry gets BOOT_TRIES
# tries before the next: docs/REFERENCE.md#fallback

# The templates live with the Recovery, which every image carries.
boot_data() { printf '%s/recovery/data' "$(product_dir)"; }

export BOOT_TRIES=3

# Outside EFI/Linux: systemd-boot lists UKIs there on its own, beside the entries
# that count tries.
export UKI_DIR=/boot/EFI/arch-os

# Boot images of kind $1, uki or image, main before fallback.
images_of() {
    if [ "$1" = uki ]; then
        printf '%s/arch-%s.efi\n%s/arch-%s-fallback.efi\n' "$UKI_DIR" "$KERNEL" "$UKI_DIR" "$KERNEL"
    else
        printf '/boot/initramfs-%s.img\n/boot/initramfs-%s-fallback.img\n' "$KERNEL" "$KERNEL"
    fi
}

# Written beside, flushed and renamed over, so the next boot reads the old file
# or the new one, never half. FAT has no journal to order the two.
place() {
    printf '%s\n' "$2" >"${1}.new"
    sync "${1}.new"
    mv -f "${1}.new" "$1"
}

# mkinitcpio preset in the system at $1 for kind $2.
boot_preset() {
    local images text
    mapfile -t images < <(images_of "$2")
    text="$(render "$(boot_data)/$2.preset" KERNEL="$KERNEL" DEFAULT="${images[0]}" FALLBACK="${images[1]}")"
    place "$1/etc/mkinitcpio.d/${KERNEL}.preset" "$text"
}

# The kernel image mkinitcpio builds kernel $2 of the system at $1 from: its
# preset's ALL_kver, else /boot, as mkinitcpio's own preset has it.
kernel_image() {
    local preset="$1/etc/mkinitcpio.d/$2.preset" kver=""
    [ ! -f "$preset" ] || kver="$(sed -n 's|^ALL_kver="\(/[^"]*\)"$|\1|p' "$preset")"
    printf '%s' "${kver:-/boot/vmlinuz-$2}"
}

# Each kernel image of the system at $1 from beside its modules, where Arch
# installs it, to where its preset builds from. A copy in /boot it no longer
# reads goes. Exit 10: modules without their image, as an interrupted removal
# leaves.
restore_kernels() {
    local root="$1" dir version pkgbase image
    for dir in "${root}/usr/lib/modules/"*/; do
        [ -e "${dir}kernel" ] || continue
        version="$(basename "$dir")"
        if [ ! -f "${dir}vmlinuz" ] || [ ! -s "${dir}pkgbase" ]; then
            echo "No kernel image beside the modules of ${version}." >&2
            exit 10
        fi
        pkgbase="$(<"${dir}pkgbase")"
        image="${root}$(kernel_image "$root" "$pkgbase")"
        mkdir -p "$(dirname "$image")"
        # Replaces the old image only once complete.
        cp "${dir}vmlinuz" "${image}.new"
        sync "${image}.new"
        mv -f "${image}.new" "$image"
        [ "$image" = "${root}/boot/vmlinuz-${pkgbase}" ] || rm -f "${root}/boot/vmlinuz-${pkgbase}"
        echo "restored vmlinuz-${pkgbase} from the modules of ${version}"
    done
}

# Boot entries, loader.conf and the boot-tries unit in the system at $1 for kind
# $2, with command line $3 for kind image. Each new entry is in place before the
# old one goes.
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

# A LoaderEntryDefault left by an earlier system boots however often it fails
# and defeats the tries.
clear_loader_default() {
    [ -e /sys/firmware/efi/efivars/LoaderEntryDefault-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f ] || return 0
    bootctl set-default '' || echo "firmware default boot entry not cleared" >&2
}

# Logs and kills what still holds the target. Why -R and -M:
# docs/CONTRIBUTING.md#closing-the-target
unmount_target() {
    mountpoint -q "$MNT" || return 0
    umount -R "$MNT" && return 0

    echo "target busy, held by:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel releases the files with a delay

    umount -R "$MNT"
}

# Every file sbctl signs and every EFI binary on the EFI partition, as sbctl
# verify lists them: 1 signed, 0 not, -1 missing. It exits 0 regardless.
boot_chain_signed() {
    local files
    files="$(arch-chroot "$1" sbctl verify --json)" || return 1
    if ! jq -e 'length > 0 and all(.[]; .is_signed == 1)' <<<"$files" >/dev/null; then
        echo "sbctl: not every boot file is signed: ${files}" >&2
        return 1
    fi
}

# On the terminal the runtime hands over, with HOME, which a service lacks. The
# shell's exit status is the user's, not a failure.
open_shell() {
    clear
    echo "Shell in ${MNT}."
    echo "Leave with exit."
    echo
    HOME=/root arch-chroot "$MNT" || true
}

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING | Files a task ships
# ////////////////////////////////////////////////////////////////////////////

# {{NAME}} filled from NAME=value, every $ kept. Unfilled placeholders and unused
# values fail. Why not envsubst: docs/CONTRIBUTING.md#templates
render() {
    local template="$1" open='{{' close='}}' text rendered="" name pair
    local -A values=() used=()
    shift

    [ -f "$template" ] || {
        echo "template ${template} not found" >&2
        return 1
    }

    for pair in "$@"; do
        name="${pair%%=*}"
        [[ $pair == *=* && $name =~ ^[A-Z][A-Z0-9_]*$ ]] || {
            echo "${template}: ${pair} is not NAME=value" >&2
            return 1
        }
        values["$name"]="${pair#*=}"
    done

    # read keeps trailing newlines, which $(<file) strips.
    IFS= read -r -d '' text <"$template" || true

    # One pass, left to right, so a value holding {{ is never parsed as a placeholder.
    while [[ $text == *"$open"* ]]; do
        rendered+="${text%%"$open"*}"
        text="${text#*"$open"}"
        name="${text%%"$close"*}"
        if [[ $text != *"$close"* || ! $name =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            echo "${template}: ${open} opens no placeholder" >&2
            return 1
        fi
        if [[ ! -v values[$name] ]]; then
            echo "${template}: no value for ${open}${name}${close}" >&2
            return 1
        fi
        rendered+="${values[$name]}"
        used["$name"]=1
        text="${text#*"$close"}"
    done

    for name in "${!values[@]}"; do
        [[ -v used[$name] ]] || {
            echo "${template}: ${name} unused" >&2
            return 1
        }
    done

    printf '%s' "${rendered}${text}"
}

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING | Region
# ////////////////////////////////////////////////////////////////////////////

# Keyboard, font and time zone come from the Installer's data/, not from the
# locale's shape: de_CH is not de.
installer_data() { printf '%s/installer/data' "$(product_dir)"; }

# Column $1 of data/languages for locale $2: its own row, else its language's.
language_field() {
    awk -v col="$1" -v locale="${2%%.*}" '
        BEGIN { lang = locale; sub(/_.*/, "", lang) }
        /^#/ || NF == 0 { next }
        $1 == locale { hit = $0; exit }
        $1 == lang && fallback == "" { fallback = $0 }
        END { split(hit != "" ? hit : fallback, f); print f[col] }
    ' "$(installer_data)/languages"
}

# Column $1 of data/countries for territory code $2, empty for none.
country_field() {
    awk -F'\t' -v col="$1" -v code="$2" 'code != "" && $1 == code { print $col }' "$(installer_data)/countries"
}

# Layouts and variants localectl converts console keymap $1 to, as "layouts
# variants" with - for none: the first row of systemd's table that xkb has, as
# localed verifies it. Empty for a keymap the table lacks.
converted_keymap() {
    awk -v keymap="$1" '
        FNR == 1 { file++ }
        file == 1 && /^! / { section = $2; next }
        file == 1 && section == "layout" && NF { layouts[$1] }
        file == 1 && section == "variant" && NF { variants[$2 $1] }
        file == 2 && !/^#/ && $1 == keymap {
            n = split($2, layout, ",")
            split($4 == "-" ? "" : $4, variant, ",")
            known = 1
            for (i = 1; i <= n; i++)
                known = known && (layout[i] in layouts) && (variant[i] == "" || (layout[i] ":" variant[i]) in variants)
            if (known) { print $2, $4; exit }
        }
    ' /usr/share/X11/xkb/rules/base.lst /usr/share/systemd/kbd-model-map
}

# What auto resolves to, also shown in each list's auto row.

# The console keyboard as localectl converts it, else as data/languages names
# it, else xkb's us. A language on its own console keymap keeps its layouts,
# since the console lacks some scripts: ar has us there and ara,us on the desktop.
auto_layout() {
    local layout keymap="$ARCH_OS_VCONSOLE_KEYMAP"
    if [ "$keymap" = "$(language_field 2 "$ARCH_OS_LOCALE_LANG")" ]; then
        layout="$(language_field 3 "$ARCH_OS_LOCALE_LANG")"
    else
        layout="$(converted_keymap "$keymap")"
        layout="${layout%% *}"
        [ -n "$layout" ] || layout="$(awk -v keymap="$keymap" '!/^#/ && $2 == keymap { print $3; exit }' "$(installer_data)/languages")"
    fi
    printf '%s' "${layout:-us}"
}

# The variant converted with the console keyboard, while the desktop keeps the
# layouts it came with.
auto_variant() {
    local converted
    converted="$(converted_keymap "$ARCH_OS_VCONSOLE_KEYMAP")"
    if [ -n "$converted" ] && [ "${converted%% *}" = "$(desktop_layout)" ] && [ "${converted#* }" != - ]; then
        printf '%s' "${converted#* }"
    else
        printf none
    fi
}

# none, not empty: the console keeps its font, and reflector ranks every mirror.
auto_font() {
    local font
    font="$(language_field 4 "$ARCH_OS_LOCALE_LANG")"
    printf '%s' "${font:-none}"
}

# none is an answer and means unset.
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# Answer $1 as applied, auto resolved by function $2.
resolved() {
    local value="$1"
    if [ -z "$value" ] || [ "$value" = "auto" ]; then
        value="$("$2")"
    fi
    not_none "$value"
}

desktop_layout() { resolved "$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" auto_layout; }
desktop_variant() { resolved "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT" auto_variant; }
mirror_country() { not_none "$ARCH_OS_REFLECTOR_COUNTRY"; }

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING | Hardware and boot chain
# ////////////////////////////////////////////////////////////////////////////

microcode() {
    if grep -q GenuineIntel /proc/cpuinfo; then
        echo intel-ucode
    elif grep -q AuthenticAMD /proc/cpuinfo; then
        echo amd-ucode
    fi
}

# Each GPU as vendor, tab, PCI device ID. A virtual machine's adapter matches
# none of the three.
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

# Secure Boot always means a UKI: https://wiki.archlinux.org/title/Unified_kernel_image
secure_boot_wanted() {
    [ "$ARCH_OS_SECURE_BOOT_ENABLED" = "true" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]
}

boot_kind() { if secure_boot_wanted; then echo uki; else echo image; fi; }

# A check against the other kind's images checks nothing.
boot_images() { images_of "$(boot_kind)"; }

# The Recovery image the ISO carries beside the Installer. Boot flow:
# docs/REFERENCE.md
export RECOVERY_IMAGE=/opt/arch-os-recovery

# On the EFI partition, where systemd-boot lists it on its own.
export RECOVERY_EFI=/boot/EFI/Linux/arch-os-recovery.efi

# Recovery partition size: twice the image, so an update can grow.
export RECOVERY_MIB=1024

# ////////////////////////////////////////////////////////////////////////////
# INSTALLING | Into the new system
# ////////////////////////////////////////////////////////////////////////////

# Retried, since the network fails. pacman's own timeout moves a dead mirror's
# download to the next.
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

# Drop-in $1 from stdin, removed if visudo rejects it: one invalid file there
# breaks all of sudo. https://wiki.archlinux.org/title/Sudo
sudoers_rule() {
    local file="${MNT}/etc/sudoers.d/${1}"
    mkdir -p "${MNT}/etc/sudoers.d"
    cat >"$file"
    chmod 0440 "$file"
    arch-chroot "$MNT" visudo -cqf "/etc/sudoers.d/${1}" && return 0
    rm -f "$file"
    echo "sudo rule ${1} rejected and removed" >&2
    return 1
}

# pacman has no drop-in directory, so each file gets its own Include: a glob
# matching nothing stops pacman. https://man.archlinux.org/man/pacman.conf.5
pacman_include() {
    local file
    file="/etc/pacman.d/$(basename "$1")"
    render "$1" >"${MNT}${file}"
    grep -qxF "Include = ${file}" "${MNT}/etc/pacman.conf" ||
        echo "Include = ${file}" >>"${MNT}/etc/pacman.conf"
}

# Attempts, and seconds per attempt: a build that hits the limit has hung.
AUR_RETRIES=3
AUR_TIMEOUT=2700

# Built as the user, with passwordless sudo for pacman only and for the build
# only. One compile job per GiB of RAM: docs/REFERENCE.md
chroot_aur_install() {
    local repo="$1"
    local url="https://aur.archlinux.org/${repo}.git"
    local dir jobs cores build until status=1 i

    chroot_pacman_install git base-devel

    jobs=$(($(awk '/^MemTotal:/ { print $2 }' /proc/meminfo) / 1048576))
    cores="$(nproc)"
    [ "$jobs" -lt 1 ] && jobs=1
    [ "$jobs" -gt "$cores" ] && jobs="$cores"

    dir="$(mktemp -u "/home/${ARCH_OS_USERNAME}/.aur-${repo}.XXXX")"
    build="rm -rf ${dir} && git clone --depth 1 ${url} ${dir} && cd ${dir}"
    # Appended to the PKGBUILD's options, so a !lto there stays.
    build="${build} && printf '\noptions+=(\"!debug\")\n' >>PKGBUILD"
    # make takes its jobs from a makepkg.conf read last, since makepkg.conf
    # overrides MAKEFLAGS from the environment. cargo reads its variable, and its
    # caches stay in the build directory, not 100 MB in the new home.
    build="${build} && mkdir -p ${dir}/.config/pacman"
    build="${build} && echo 'MAKEFLAGS=\"-j${jobs}\"' >${dir}/.config/pacman/makepkg.conf"
    build="${build} && XDG_CONFIG_HOME=${dir}/.config CARGO_BUILD_JOBS=${jobs}"
    build="${build} CARGO_HOME=${dir}/.cargo XDG_CACHE_HOME=${dir}/.cache"
    build="${build} makepkg -si --noconfirm --needed"

    # makepkg -si needs root only for pacman. The rule expires after the longest
    # possible run, so an aborted run leaves no passwordless sudo.
    until="$(date -u -d "+$((AUR_RETRIES * (AUR_TIMEOUT + RETRY_WAIT))) seconds" '+%Y%m%d%H%M%SZ')"
    echo "%wheel ALL=(ALL:ALL) NOTAFTER=${until} NOPASSWD: /usr/bin/pacman" | sudoers_rule 99-aur-build

    echo "building ${repo} from the AUR with ${jobs} job(s)"
    for ((i = 1; i <= AUR_RETRIES; i++)); do
        [ "$i" -gt 1 ] && echo "retry ${i}/${AUR_RETRIES}: building ${repo} from the AUR"
        status=0
        as_user "timeout ${AUR_TIMEOUT} bash -c $(printf '%q' "$build")" || status=$?
        [ "$status" -eq 0 ] && break
        if [ "$status" -eq 124 ]; then
            echo "building ${repo} from the AUR stopped after $((AUR_TIMEOUT / 60)) minutes" >&2
            break
        fi
        sleep "$RETRY_WAIT"
    done

    # Revoked before anything can fail, or passwordless sudo stays.
    rm -f "${MNT}/etc/sudoers.d/99-aur-build"
    rm -rf "${MNT}${dir}" || echo "build directory ${dir} not removed" >&2

    [ "$status" -eq 0 ] && return 0
    echo "building ${repo} from the AUR failed" >&2
    check_online || exit "$EXIT_OFFLINE"
    fetch_url -sI --max-time 20 https://aur.archlinux.org >/dev/null || exit "$EXIT_AUR"
    return "$status"
}

# As the user, since makepkg refuses root. env -i hides passwords from every
# build script and drops root's runtime directory, which the user cannot write.
as_user() {
    arch-chroot "$MNT" /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- env -i \
        HOME="/home/${ARCH_OS_USERNAME}" USER="$ARCH_OS_USERNAME" LOGNAME="$ARCH_OS_USERNAME" \
        PATH="$PATH" LANG=C.UTF-8 bash -c "$1"
}

# Accounts a package of the Installer's choices creates through sysusers.d,
# beyond the live system's own. The Desktop run of e2e.sh holds the list to an
# installed system.
PACKAGE_ACCOUNTS="_talkd avahi colord cups docker flatpak fwupd gamemode gdm geoclue git gnome-remote-desktop malcontent-timer-ext-agent malcontent-timerd malcontent-webd nm-openvpn openvpn passim pcscd polkitd rpc rpcuser rtkit saned usbmux vboxsf"

# A name the live system or a package claims: useradd fails on it after the
# wipe, or the account shares the package's rights, such as docker's socket.
reserved_name() {
    if getent passwd "$1" >/dev/null || getent group "$1" >/dev/null; then
        return 0
    fi
    [[ " ${PACKAGE_ACCOUNTS} " == *" $1 "* ]]
}

# Desktop entry of the chosen browser. Two differ from their package name.
browser_entry() {
    case "$ARCH_OS_BROWSER" in
    epiphany) echo org.gnome.Epiphany.desktop ;;
    vivaldi) echo vivaldi-stable.desktop ;;
    *) echo "${ARCH_OS_BROWSER}.desktop" ;;
    esac
}

# The user's home in the new system, seen from the live system.
user_home() { printf '%s/home/%s' "$MNT" "$ARCH_OS_USERNAME"; }

# Hands the home back to the user: what root wrote is root's.
own_home() {
    arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"
}

# Inside the new system: from outside, an absolute link in its /usr/bin
# resolves into the live system.
has_command() { arch-chroot "$MNT" test -x "/usr/bin/${1}"; }

# Output, not status: verify skips an unreadable key with a warning and exits 0.
# --man=no, since the live system ships no manuals.
unit_complaints() { systemd-analyze verify --man=no --root="$MNT" -- "$@" 2>&1; }

# sysctl ignores unknown keys silently, so each is checked under /proc/sys.
sysctl_keys_exist() {
    local keys key
    keys="$(sed -n 's/^[[:space:]]*\([a-z][a-z0-9._-]*\)[[:space:]]*=.*/\1/p' "$1")"

    # An empty key list would pass unchecked.
    [ -n "$keys" ] || {
        echo "${1}: no keys" >&2
        return 1
    }

    while read -r key; do
        [ -e "/proc/sys/${key//.//}" ] || {
            echo "${1}: ${key} unknown to this kernel" >&2
            return 1
        }
    done <<<"$keys"
}

# ////////////////////////////////////////////////////////////////////////////
# REPAIRING | Target system
# ////////////////////////////////////////////////////////////////////////////

# Mapper name of the unlocked disk.
export CRYPT=recovery

# btrfs top level for rollbacks. Outside MNT, so no chroot sees it and
# unmounting MNT keeps it.
export BTRFS_TOP=/run/arch-os-recovery

# The system partition if it is LUKS or btrfs labeled BTRFS. -r keeps an empty
# column.
target_partition() {
    local part
    part="$(system_partition "$ARCH_OS_RECOVERY_DISK")"
    lsblk -dnro FSTYPE,LABEL "$part" 2>/dev/null | awk -F'[ ]' -v part="$part" '
        $1 == "crypto_LUKS" || ($1 == "btrfs" && $2 == "BTRFS") { print part }'
}

target_device() {
    if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
        printf '/dev/mapper/%s' "$CRYPT"
    else
        target_partition
    fi
}

# Without -d, an unlocked LUKS partition reports the btrfs inside.
fstype() { lsblk -dno FSTYPE "$1" 2>/dev/null || true; }

# Mounted by the Installer's layout, @ first, then /boot. Not by fstab, which
# may be broken.
mount_target() {
    local device subvolume path
    device="$(target_device)"
    while IFS=$'\t' read -r subvolume path; do
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" "$device" "${MNT}${path%/}"
    done < <(btrfs_subvolumes)
    mount_esp "${MNT}/boot"
}

# The EFI partition, checked first as the system checks it at boot: a start
# broken during a write leaves FAT inconsistent, and a repair writes there.
# fsck.fat exits 1 for errors it fixed.
mount_esp() {
    local esp
    esp="$(boot_partition "$ARCH_OS_RECOVERY_DISK")"
    fsck.fat -a "$esp" || allow 1
    mount --mkdir -t vfat "$esp" "$1"
}

# Also closes what an earlier run left open. Unmounted first, since a mounted
# system cannot be locked.
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
# REPAIRING | Recovery update
# ////////////////////////////////////////////////////////////////////////////

# Booted from the Recovery partition of the disk it repairs: archisodevice names
# that partition's UUID.
on_recovery_partition() {
    local uuid
    uuid="$(sed -n 's/.*archisodevice=UUID=\([^ ]*\).*/\1/p' /proc/cmdline)"
    [ -n "$uuid" ] && [ -n "$ARCH_OS_RECOVERY_DISK" ] &&
        [ "$(blkid -p -s UUID -o value "$(recovery_partition "$ARCH_OS_RECOVERY_DISK")" 2>/dev/null)" = "$uuid" ]
}

# The disk's Recovery boots if systemd-boot lists an image naming its partition's
# UUID. An aborted update leaves them apart.
recovery_starts() {
    local uuid esp mnt listed="" status=0
    uuid="$(blkid -p -s UUID -o value "$(recovery_partition "$ARCH_OS_RECOVERY_DISK")")" || return 1
    esp="$(boot_partition "$ARCH_OS_RECOVERY_DISK")"
    mnt="$({ findmnt -nro TARGET -S "$esp" || allow 1; } | awk '!found { print; found = 1 }')"
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

# Newest stable Recovery of this major series in releases JSON on stdin: version,
# URL, sha256. Another series may expect another disk layout.
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

# What an update installs, as newest_recovery prints it, or nothing. On the
# Recovery partition only a newer one, elsewhere the newest if the disk's
# Recovery does not boot.
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
# THE YAML | Functions called as name()
# ////////////////////////////////////////////////////////////////////////////
#
# A setting's function is named after its key, an action's after its effect. A
# list line may hold value, tab, label.

# Whole writable disks, labeled with size and model. Read-only ones, such as an
# eMMC's boot areas, take no installation.
options_disks() {
    lsblk -dn -o PATH,TYPE,RO,SIZE,MODEL | awk -v live="$(live_disk)" '
        $2 != "disk" || $3 != 0 || $1 == live || $1 ~ /^\/dev\/zram/ { next }
        { path = $1; $1 = ""; $2 = ""; $3 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

options_keymaps() { localectl list-keymaps; }

# Networks in range, strongest first, after the scan ends. Columns split on two
# spaces, since an SSID may hold one.
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

# The Arch ISO records the live system's keymap only as a loadkeys line in
# root's history.
live_keymap() {
    { grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' '
}

# The live system's keymap, else the interface language's.
prefill_keymap() {
    local keymap
    keymap="$(live_keymap)"
    keymap="${keymap:-$(language_field 2 "$MODULE_LANGUAGE")}"
    printf '%s' "${keymap:-us}"
}

# --test-passphrase only checks the keyslots.
unlocks() { printf '%s' "$1" | cryptsetup open --test-passphrase "$(target_partition)"; }

restart_machine() { systemctl reboot; }

shut_down_machine() { systemctl poweroff; }

no_cable() {
    if online_by_cable; then
        return 1
    fi
}

# ─── The Installer ─────────────────────────────────────────────────────────

# UTF-8 locales glibc supports, without @ variants. SUPPORTED, not locale.gen,
# which hand edits change.
options_locales() {
    sed -n 's/^\([a-z]\{2,3\}\(_[A-Z]\{2\}\)\{0,1\}\)\(\.UTF-8\)\{0,1\} UTF-8$/\1/p' /usr/share/i18n/SUPPORTED | sort -u
}

# The interface language's own country locale: de gives de_DE. Else en_US,
# which is generated anyway, not Afar from the first row.
prefill_locale() {
    local lang="$MODULE_LANGUAGE"
    if [[ $lang =~ ^[a-z]{2,3}$ ]] && grep -q "^${lang}_${lang^^}\(\.UTF-8\)\{0,1\} UTF-8$" /usr/share/i18n/SUPPORTED; then
        printf '%s_%s' "$lang" "${lang^^}"
        return 0
    fi
    printf 'en_US'
}

# Loaded on answer, so the next input uses it.
apply_vconsole_keymap() {
    dry_run && return 0
    loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
}

# kbd's fonts, which every installation has, not the console font folder, which
# also holds the ISO's own fonts.
options_fonts() {
    printf 'auto\tauto (%s)\n' "$(auto_font)"
    echo none
    pacman -Qlq kbd | sed -n 's|^/usr/share/kbd/consolefonts/\([^/]*\)\.psfu\{0,1\}\(\.gz\)\{0,1\}$|\1|p' | sort -u
}

options_timezones() { timedatectl list-timezones; }

# The chosen country's zone, UTC rather than Africa/Abidjan for none.
prefill_timezone() {
    local locale="${ARCH_OS_LOCALE_LANG%%.*}" territory="" zone
    [[ $locale == *_* ]] && territory="${locale#*_}"
    zone="$(country_field 3 "$territory")"
    printf '%s' "${zone:-UTC}"
}

# Applied to the live system at once, so the log uses the target's zone. Only
# /etc/localtime changes, the hardware clock stays.
apply_timezone() {
    dry_run && return 0
    timedatectl set-timezone "$ARCH_OS_TIMEZONE"
}

options_countries() {
    echo none
    # "-" marks a country without an Arch mirror.
    awk -F'\t' '!/^#/ && $2 != "-" { print $2 }' "$(installer_data)/countries"
}

value_virtual_machine() { if systemd-detect-virt -q; then echo true; else echo false; fi; }

options_layouts() {
    printf 'auto\tauto (%s)\n' "$(auto_layout)"
    localectl list-x11-keymap-layouts
}

options_variants() {
    local layout
    layout="$(desktop_layout)"
    [ -n "$layout" ] || return 0

    printf 'auto\tauto (%s)\n' "$(auto_variant)"
    echo none
    # localectl exits 1 for a layout without variants. The layout comes from the
    # same file, so it exists. A variant applies to the first of several.
    localectl list-x11-keymap-variants "${layout%%,*}" 2>/dev/null || allow 1
}

booted_in_uefi() { [ -d /sys/firmware/efi ]; }

# Captured first: grep -q exits at the first match, and bootctl would fail under
# pipefail.
secure_boot_off() { grep -q "Secure Boot: disabled" <<<"$(bootctl status 2>/dev/null)"; }

import_config() {
    local ref url out body
    # The paste code from a full link or the code alone, always fetched from paste.rs.
    ref="$(printf '%s' "$ARCH_OS_CONFIG_SOURCE" | tr -d '[:space:]')"
    url="${PASTE}/${ref##*/}"
    # The HTTP status last, which curl writes on failure too.
    if ! out="$(fetch_url -sS --max-time 30 --retry 3 --retry-delay 2 -w '\n%{http_code}' "$url")"; then
        [ "${out##*$'\n'}" != 404 ] || exit 11
        paste_failed
    fi

    # Without the sharing keys and the source machine's own: DISK, which may name
    # another disk here, and KERNEL_ARGS and SSH_KEY, which let a stranger in.
    body="$(printf '%s\n' "${out%$'\n'*}" | grep '^ARCH_OS_[A-Z0-9_]*=' |
        grep -vE '^ARCH_OS_(CONFIG_[A-Z_]*|DISK|KERNEL_ARGS|SSH_KEY)=' || allow 1)"
    [ -n "$body" ] || exit 11

    # The runtime rereads the answer file after success.
    printf '%s\n' "$body" >>"$MODULE_CONF"
}

share_config() {
    local url target
    # A demo URL under --dry-run, so the page shows one.
    if dry_run; then
        answer ARCH_OS_CONFIG_URL "${PASTE}/demo"
        return 0
    fi

    url="$(grep -v '^ARCH_OS_CONFIG_' "$MODULE_CONF" | paste_online)" || url=""
    [ -n "$url" ] || paste_failed
    answer ARCH_OS_CONFIG_URL "$url"

    # Also into the installed system's copy, which records its share URL.
    target="$(user_home)/installer.conf"
    if [ -f "$target" ]; then
        printf "ARCH_OS_CONFIG_URL='%s'\n" "$url" >>"$target"
    fi
}

# ─── The Recovery ──────────────────────────────────────────────────────────

# A LUKS header is readable without the password.
value_disk_encrypted() { [ "$(fstype "$(target_partition)")" = "crypto_LUKS" ] && echo true || echo false; }

check_disk_password() {
    dry_run && return 0
    unlocks "$ARCH_OS_RECOVERY_PASSWORD"
}

# Loaded on answer.
apply_recovery_keymap() {
    dry_run && return 0
    loadkeys "$ARCH_OS_RECOVERY_KEYMAP"
}

# Rollback choices, newest first: path, tab, then number, date and description
# from info.xml. No snapshot is an answer and skips the step.
options_snapshots() {
    local path list
    # Samples under --dry-run, for the screenshots.
    if dry_run; then
        printf '@snapshots/2/snapshot\t2   2026-08-30 21:04:17 UTC   after a system update\n'
        printf '@snapshots/1/snapshot\t1   2026-08-29 09:12:40 UTC   first root filesystem\n'
        return 0
    fi

    # Listed first, so a btrfs that cannot list fails the rollback instead of
    # skipping it. Sorted by snapper's number, not btrfs order.
    list="$(btrfs subvolume list -o "${BTRFS_TOP}/@snapshots")" || return 1
    [ -n "$list" ] || return 0
    while read -r path; do
        printf '%s\t%s\n' "$path" "$(snapshot_label "$(printf '%s' "$path" | cut -d/ -f2)")"
    done < <(awk '{ print $NF }' <<<"$list" | sort -t/ -k2 -rn)
}

# Field by field, so a broken info.xml loses a column, not the list.
snapshot_label() {
    local info="${BTRFS_TOP}/@snapshots/${1}/info.xml"
    local date="" description=""
    if [ -r "$info" ]; then
        date="$(sed -n '0,/<date>.*<\/date>/s:.*<date>\(.*\)</date>.*:\1:p' "$info")"
        description="$(sed -n '0,/<description>.*<\/description>/s:.*<description>\(.*\)</description>.*:\1:p' "$info")"
    fi
    printf '%s' "$1"
    [ -z "$date" ] || printf '   %s UTC' "$date" # snapper records UTC
    [ -z "$description" ] || printf '   %s' "$description"
    echo
}

# On the Recovery partition, or elsewhere when the disk's Recovery does not boot
# after an aborted update. The Recovery partition is the third, labeled recovery.
recovery_to_update() {
    if on_recovery_partition; then
        return 0
    fi
    [ -n "$ARCH_OS_RECOVERY_DISK" ] || return 1
    [ "$(lsblk -dno PARTLABEL "$(recovery_partition "$ARCH_OS_RECOVERY_DISK")" 2>/dev/null)" = recovery ] && ! recovery_starts
}

# Yes if there is nothing to install. No opens the install. GitHub is asked
# first, since archlinux.org may be down while GitHub answers.
recovery_up_to_date() {
    local json found
    if ! json="$(releases_json)"; then
        check_online || exit "$EXIT_OFFLINE"
        exit "$EXIT_UNREACHABLE"
    fi
    found="$(recovery_update <<<"$json")"
    [ -z "$found" ]
}

check_update_password() {
    dry_run && return 0
    unlocks "$ARCH_OS_RECOVERY_UPDATE_PASSWORD"
}

# Checksum, size and signing come before the partition is written. The boot
# image replaces the old one after read-back, so both disagree only during the
# write. The disk opens before the download, which lives in memory beside the
# up to 1 GiB that unlocking takes.
install_recovery_update() {
    local tar=/tmp/arch-os-recovery-update.tar
    # EFI partition mount point while the system stays closed.
    local esp_mnt=/run/arch-os-esp
    local json found version url digest stem part size room esp want have

    if ! json="$(releases_json)"; then
        check_online || exit "$EXIT_OFFLINE"
        exit "$EXIT_UNREACHABLE"
    fi
    found="$(recovery_update <<<"$json")"
    if [ -z "$found" ]; then
        echo "no Recovery to install" >&2
        exit 1
    fi
    read -r version url digest <<<"$found"

    # Leftovers of an earlier attempt go first. Arch OS signs its boot chain only
    # behind encryption, so an encrypted system is mounted for its keys.
    close_target
    if mountpoint -q "$esp_mnt"; then
        umount "$esp_mnt"
    fi
    if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
        printf '%s' "$ARCH_OS_RECOVERY_UPDATE_PASSWORD" | cryptsetup open "$(target_partition)" "$CRYPT"
        mount_target
        esp="${MNT}/boot"
    else
        mount_esp "$esp_mnt"
        esp="$esp_mnt"
    fi

    echo "fetching ${url##*/}"
    if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "${tar}.part"; then
        rm -f "${tar}.part"
        check_online || exit "$EXIT_OFFLINE"
        echo "downloading ${url##*/} failed" >&2
        exit 10
    fi
    if ! echo "${digest}  ${tar}.part" | sha256sum -c - >/dev/null; then
        rm -f "${tar}.part"
        echo "${url##*/}: checksum mismatch, deleted" >&2
        exit 11
    fi
    mv -f "${tar}.part" "$tar"

    stem="arch-os-${version}-recovery"
    part="$(recovery_partition "$ARCH_OS_RECOVERY_DISK")"
    size="$(tar -tvf "$tar" "${stem}/recovery.img" | awk '{ print $3 }')"
    room="$(blockdev --getsize64 "$part")"
    if [ -z "$size" ] || [ "$size" -gt "$room" ]; then
        echo "Recovery ${version} needs ${size:-?} bytes, ${part} holds ${room}" >&2
        exit 12
    fi

    # A leftover copy takes room the kernel images need. Global, since the EXIT
    # trap reads it after return.
    efi="${esp}${RECOVERY_EFI#/boot}"
    rm -f "${efi}.new"
    trap 'rm -f "${efi}.new"' EXIT
    tar -xOf "$tar" "${stem}/recovery.efi" >"${efi}.new"

    # Signed where the system has sbctl, like its other boot files.
    if [ "$esp" != "$esp_mnt" ] && [ -x "${MNT}/usr/bin/sbctl" ]; then
        arch-chroot "$MNT" sbctl sign "${RECOVERY_EFI}.new"
    fi

    # Asked again right before the write, since a disk plugged in meanwhile may
    # carry the name.
    if ! recovery_to_update; then
        echo "${part} is no longer the Recovery to update" >&2
        exit 1
    fi
    echo "writing Recovery ${version} to ${part}"
    if ! tar -xOf "$tar" "${stem}/recovery.img" | dd of="$part" bs=4M conv=fsync status=none; then
        echo "writing ${part} failed" >&2
        exit 13
    fi

    # Flushed, so the hash reads the disk, not the page cache.
    blockdev --flushbufs "$part"
    want="$(tar -xOf "$tar" "${stem}/recovery.img" | sha256sum)"
    have="$(head -c "$size" "$part" | sha256sum)"
    if [ "$have" != "$want" ]; then
        echo "${part}: read-back differs from Recovery ${version}" >&2
        exit 13
    fi
    sync "${efi}.new"
    mv -f "${efi}.new" "$efi"
    sync
    if [ "$esp" = "$esp_mnt" ]; then
        umount "$esp_mnt"
    fi
    close_target
    rm -f "$tar"
    echo "Recovery ${version} installed"
}
