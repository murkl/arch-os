#!/usr/bin/env bash
# lib.sh's pure functions against expected answers. What reads the machine is
# tested beside each task.
#
#   lib.check.sh
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh

status=0
expect() {
    if [ "$2" != "$3" ]; then
        printf '%s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3" >&2
        status=1
    fi
}

# Exit status as yes or no.
holds() { if "$@"; then echo yes; else echo no; fi; }

# ─── Statuses ────────────────────────────────────────────────────────────────

while read -r code want; do
    expect "allow 1 3 after ${code}" "$(holds eval "(exit ${code}) || allow 1 3")" "$want"
done <<'EOF'
0 yes
1 yes
2 no
3 yes
EOF

# ─── Versions ────────────────────────────────────────────────────────────────

while read -r one other want; do
    expect "newer ${one} ${other}" "$(holds newer "$one" "$other")" "$want"
done <<'EOF'
2.1.0 2.0.0 yes
2.0.0 2.1.0 no
2.0.10 2.0.9 yes
2.10.0 2.9.0 yes
3.0.0 2.99.99 yes
2.0.0 2.0.0 no
2.0.1 2.0.1-dev yes
2.0.1-dev 2.0.1 no
2.0.1-dev 2.0.0 yes
2.0.0 2.0.1-dev no
2.0.1-dev 2.0.1-dev no
2.0.1-rc2 2.0.1-rc1 yes
EOF

# ─── GitHub's releases ───────────────────────────────────────────────────────

# GitHub's field order, newest first: another series, a pre-release, a release
# without digest, and a label and body that contain the searched patterns.
asset() {
    printf '{"url":"https://api.github.com/repos/murkl/arch-os/releases/assets/%s","id":%s,"name":"%s","label":"%s","uploader":{"url":"https://api.github.com/users/murkl"},"size":1,"digest":%s,"browser_download_url":"https://github.com/murkl/arch-os/releases/download/%s/%s"}' \
        "$1" "$1" "$3" "${5:-}" "$4" "$2" "$3"
}
release() {
    local version="$1"
    shift
    printf '{"url":"https://api.github.com/repos/murkl/arch-os/releases/%s","assets_url":"https://api.github.com/repos/murkl/arch-os/releases/%s/assets","tag_name":"%s","draft":false,"prerelease":%s,"assets":[%s],"tarball_url":"https://api.github.com/repos/murkl/arch-os/tarball/%s","body":"%s"}' \
        "${version//[^0-9]/}" "${version//[^0-9]/}" "$version" "$([[ $version == *-* ]] && echo true || echo false)" "$(
            IFS=,
            echo "$*"
        )" "$version" 'Fixes, \"url\": \"x/releases/assets/1\", and \"browser_download_url\": \"y-recovery-x86_64.tar\"'
}
compact="[$(
    release 3.0.0 "$(asset 30 3.0.0 arch-os-3.0.0-recovery-x86_64.tar '"sha256:30"')"
    printf ,
    release 2.2.0-rc1 "$(asset 22 2.2.0-rc1 arch-os-2.2.0-rc1-recovery-x86_64.tar '"sha256:22"')"
    printf ,
    release 2.1.0 \
        "$(asset 211 2.1.0 arch-os-2.1.0-x86_64.iso '"sha256:211"')" \
        "$(asset 212 2.1.0 arch-os-2.1.0-recovery-x86_64.tar '"sha256:212"' 'Recovery, as one tar')"
    printf ,
    release 2.0.1 "$(asset 201 2.0.1 arch-os-2.0.1-recovery-x86_64.tar null)"
    printf ,
    release 2.0.0 "$(asset 200 2.0.0 arch-os-2.0.0-recovery-x86_64.tar '"sha256:200"')"
)]"

# The same, pretty-printed with a space after each colon.
pretty="$(sed -e 's/":/": /g' -e 's/,"/,\n  "/g' -e 's/{/{\n  /g' -e 's/}/\n}/g' <<<"$compact")"

recovery() { printf 'https://github.com/murkl/arch-os/releases/download/%s/arch-os-%s-recovery-x86_64.tar' "$1" "$1"; }

for layout in compact pretty; do
    json="$compact"
    [ "$layout" = compact ] || json="$pretty"

    expect "asset_in .iso, ${layout}" "$(asset_in .iso <<<"$json")" \
        "https://github.com/murkl/arch-os/releases/download/2.1.0/arch-os-2.1.0-x86_64.iso 211"
    expect "asset_in -recovery-x86_64.tar, ${layout}" "$(asset_in -recovery-x86_64.tar <<<"$json" | cut -d' ' -f2 | paste -sd' ')" \
        "30 22 212  200"
    expect "asset_in .zip, ${layout}" "$(asset_in .zip <<<"$json")" ""

    while read -r running want; do
        MODULE_VERSION="$running"
        expect "newest_recovery for ${running}, ${layout}" "$(newest_recovery <<<"$json")" "$want"
    done <<EOF
2.0.0 2.1.0 $(recovery 2.1.0) 212
2.5.0 2.1.0 $(recovery 2.1.0) 212
3.0.0-dev 3.0.0 $(recovery 3.0.0) 30
4.0.0
EOF
done

# ─── The Disk's Recovery ─────────────────────────────────────────────────────

# bootctl's entries as an installed system lists them, the system's without
# options and the Recovery's naming its partition.
entries='[{"type":"type1","source":"esp","id":"main.conf","title":"Arch OS","sortKey":"arch","version":null},{"type":"type2","source":"esp","id":"arch-os-recovery.efi","title":"Arch OS Recovery","sortKey":"arch-os-recovery","version":"2.1.0","options":"archisobasedir=arch archisodevice=UUID=20df795e-7a67-4769-9f9a-54ad60c43f55 copytoram=y quiet"},{"type":"loader","source":"esp","id":"auto-reboot-to-firmware-setup","title":"Reboot Into Firmware Interface","version":null}]'
blkid() { printf '%s\n' "$disk_uuid"; }
findmnt() { echo /efi; }
bootctl() { printf '%s\n' "$listing"; }
export ARCH_OS_RECOVERY_DISK=/dev/vda
for layout in compact pretty; do
    listing="$entries"
    [ "$layout" = compact ] || listing="$(jq . <<<"$entries")"
    while read -r disk_uuid want; do
        expect "recovery_version for ${disk_uuid}, ${layout}" "$(recovery_version)" "$want"
    done <<'EOF'
20df795e-7a67-4769-9f9a-54ad60c43f55 2.1.0
20df795e-7a67-4769-9f9a-54ad60c43f5
EOF
done
unset -f blkid findmnt bootctl

# On the Recovery partition a newer one than itself. From the ISO a newer one
# than the disk's, the newest where the disk's does not boot (-).
while read -r own disk running want; do
    MODULE_VERSION="$running"
    on_recovery_partition() { [ "$own" = yes ]; }
    recovery_version() { [ "$disk" = - ] || printf '%s' "$disk"; }
    expect "recovery_update on its partition: ${own}, disk's: ${disk}, running ${running}" \
        "$(recovery_update <<<"$compact" | cut -d' ' -f1)" "$want"
done <<'EOF'
yes - 2.0.0 2.1.0
yes - 2.1.0-dev 2.1.0
yes - 2.1.0
yes - 2.1.1-dev
no 2.1.0 2.0.0
no 2.0.0 2.1.1-dev 2.1.0
no 2.1.1-dev 2.1.1-dev
no 3.0.0 2.1.1-dev
no - 2.0.0 2.1.0
no - 2.9.0-dev 2.1.0
no - 4.0.0
EOF

# ─── Files a task ships ──────────────────────────────────────────────────────

templates="$(mktemp -d)"
trap 'rm -rf "$templates"' EXIT
cat >"${templates}/plain" <<'EOF'
name={{NAME}}
path=${HOME}/$(date)

EOF
printf '{{NAME}} and {{OTHER}}\n' >"${templates}/two"
printf 'a {{ b\n' >"${templates}/open"
printf '{{lower}}\n' >"${templates}/lower"

expect "render fills and keeps every \$" "$(render "${templates}/plain" NAME=tux | od -c)" \
    "$(sed 's/{{NAME}}/tux/' "${templates}/plain" | od -c)"
expect "render keeps {{ in a value" "$(render "${templates}/two" NAME='{{OTHER}}' OTHER=x)" "{{OTHER}} and x"
expect "render with an unfilled placeholder" "$(holds render "${templates}/two" NAME=x 2>/dev/null)" no
expect "render with an unused value" "$(holds render "${templates}/plain" NAME=x EXTRA=y 2>/dev/null)" no
expect "render with a bare {{" "$(holds render "${templates}/open" 2>/dev/null)" no
expect "render with a lowercase name" "$(holds render "${templates}/lower" lower=x 2>/dev/null)" no
expect "render with no template" "$(holds render "${templates}/none" 2>/dev/null)" no

# ─── The script ──────────────────────────────────────────────────────────────

words=(sgdisk -n 2:0:-1026M "Arch OS Recovery" "it's" "" $'two\nlines' '%wheel ALL=(ALL:ALL)' '~' 'a*' "\$HOME" 'a;b')
# A broken line fails the comparison, not this script.
eval "back=($(shell_line "${words[@]}"))" 2>/dev/null || back=(unparsable)
expect "shell_line reads back as its words" "$(printf '%q ' "${back[@]}")" "$(printf '%q ' "${words[@]}")"
expect "shell_line leaves plain words bare" "$(shell_line sgdisk -t 1:ef00 -c 1:boot /dev/vda)" \
    "sgdisk -t 1:ef00 -c 1:boot /dev/vda"

# Each text through file_shell and back, byte for byte: a here-document, one
# holding its own delimiter, one without the final newline, two files at once.
for text in $'KEYMAP=de\n' $'EOF\nEOF_\n$(date) \\n\n' 'rw quiet' ''; do
    rm -f "${templates}/one" "${templates}/two"
    eval "$(file_shell ">" "$text" "${templates}/one")" >/dev/null 2>&1 || true
    eval "$(file_shell ">>" "$text" "${templates}/two" "${templates}/one")" >/dev/null 2>&1 || true
    expect "file_shell writes $(shell_line "$text")" "$(od -c "${templates}/one")" \
        "$(printf '%s%s' "$text" "$text" | od -c)"
    expect "file_shell appends $(shell_line "$text") to a second file" "$(od -c "${templates}/two")" \
        "$(printf '%s' "$text" | od -c)"
done

# What the runtime reads on fd 3: each command before it runs, on one line, and
# its confirmation once it succeeded.
recorded_by() {
    (
        export MODULE_SCRIPT="${templates}/script.sh"
        exec 3>"${templates}/fd3"
        "$@"
    ) >/dev/null 2>&1 || true
    cat "${templates}/fd3"
}
expect "run hands over its command, then confirms it" "$(recorded_by run touch "${templates}/a b")" \
    "$(printf 'cmd\ttouch %s\ncmd-ok' "$(shell_line "${templates}/a b")")"
expect "run leaves a failed command unconfirmed" "$(recorded_by run false)" "$(printf 'cmd\tfalse')"
expect "write_file hands over its here-document on one line" \
    "$(printf 'a\\b\n' | recorded_by write_file "${templates}/w")" \
    "$(printf "cmd\tcat >%s <<'EOF'\\\\na\\\\\\\\b\\\\nEOF\ncmd-ok" "${templates}/w")"
export SECRET=hunter2
reference="printf %s \"\$SECRET\" >/dev/null"
expect "run_sh hands over a password by its name" "$(recorded_by run_sh "$reference")" \
    "$(printf 'cmd\t%s\ncmd-ok' "$reference")"
unset SECRET
expect "run without a script records nothing" "$(holds run true)" yes

# as_user takes shell text, quotes included, as tasks and tests hand it over.
expect "as_user runs shell text" \
    "$(run() { printf '%s|' "${@: -3}"; } && ARCH_OS_USERNAME=tux as_user 'gjs -c "print(1)"')" \
    'bash|-c|gjs -c "print(1)"|'

# The head as the Installer's script starts: outside a live system it stops
# before anything, and on another disk too.
lsblk() { printf 'QEMU\\x20DISK  17179869184\n'; }
first="$(ARCH_OS_DISK=/dev/vda ARCH_OS_VCONSOLE_KEYMAP=de-latin1 script_head)"
unset -f lsblk
expect "script_head is bash" "$(holds bash -n -c "$first")" yes
expect "script_head loads the keyboard" "$(tail -n1 <<<"$first")" "loadkeys de-latin1"
on_live_image || expect "script_head outside a live system" "$(bash -c "$first" 2>&1 || echo "exit $?")" \
    $'Arch Linux live system required. Boot from the Arch OS ISO.\nexit 1'
disk_check="$(grep MODEL,SERIAL,SIZE <<<"$first")"
for identity in 'QEMU\x20DISK  17179869184' 'QEMU\x20DISK  34359738368'; do
    expect "script_head's disk check where lsblk names ${identity}" \
        "$(bash -c "lsblk() { printf '%s\n' '${identity}'; }; ${disk_check}" 2>&1 || echo "exit $?")" \
        "$([ "$identity" = 'QEMU\x20DISK  17179869184' ] || printf '%s\nexit 1' \
            'Disk mismatch at /dev/vda')"
done

# ─── The kernel a preset builds from ────────────────────────────────────────

for kind in uki image; do
    mkdir -p "${templates}/${kind}/etc/mkinitcpio.d"
    render "$(boot_data)/${kind}.preset" KERNEL=linux-zen DEFAULT=d FALLBACK=f \
        >"${templates}/${kind}/etc/mkinitcpio.d/linux-zen.preset"
done
case "$(kernel_image "${templates}/uki" linux-zen)" in /boot/*) off=no ;; *) off=yes ;; esac
expect "kernel_image of a uki preset is off the EFI partition" "$off" yes
expect "kernel_image of an image preset" "$(kernel_image "${templates}/image" linux-zen)" /boot/vmlinuz-linux-zen
expect "kernel_image without a preset" "$(kernel_image "${templates}/uki" linux-lts)" /boot/vmlinuz-linux-lts

# ─── The disk ────────────────────────────────────────────────────────────────

while read -r disk number want; do
    expect "part_of ${disk} ${number}" "$(part_of "$disk" "$number")" "$want"
done <<'EOF'
/dev/sda 2 /dev/sda2
/dev/vda 3 /dev/vda3
/dev/nvme0n1 1 /dev/nvme0n1p1
/dev/mmcblk0 3 /dev/mmcblk0p3
EOF

# ─── The keyboard ────────────────────────────────────────────────────────────

while read -r language want; do
    expect "prefill_keymap language ${language}" "$(MODULE_LANGUAGE="$language" prefill_keymap)" "$want"
done <<'EOF'
de de-latin1
pt_BR br-abnt2
xx us
EOF

while read -r keymap locale want; do
    expect "auto_layout ${keymap} ${locale}" \
        "$(ARCH_OS_VCONSOLE_KEYMAP="$keymap" ARCH_OS_LOCALE_LANG="$locale" auto_layout)" "$want"
done <<'EOF'
de-latin1 de_DE de
de-latin1 en_US de
us de_DE us
us ar_EG ara,us
de_CH-latin1 de_CH ch
de_CH-latin1 en_US ch
pl en_US pl
uk de_DE gb
ru en_US ru,us
ru ru_RU ru,us
il he_IL il,us
amiga-de de_DE us
EOF

while read -r keymap locale layout want; do
    expect "auto_variant ${keymap} ${locale} ${layout}" \
        "$(ARCH_OS_VCONSOLE_KEYMAP="$keymap" ARCH_OS_LOCALE_LANG="$locale" ARCH_OS_DESKTOP_KEYBOARD_LAYOUT="$layout" auto_variant)" "$want"
done <<'EOF'
de-latin1 de_DE auto none
de-latin1-nodeadkeys de_DE auto nodeadkeys
de-latin1-nodeadkeys de_DE de nodeadkeys
de-latin1-nodeadkeys de_DE fr none
fr_CH-latin1 fr_CH auto fr
dvorak en_US auto dvorak
cz-qwerty en_US auto qwerty,
ru ru_RU auto none
il he_IL auto none
amiga-de de_DE auto none
EOF

# ─── The account and the disk ────────────────────────────────────────────────

while read -r name want; do
    expect "reserved_name ${name}" "$(holds reserved_name "$name")" "$want"
done <<'EOF'
root yes
wheel yes
docker yes
gdm yes
tux no
EOF

# The smallest disks the partition task enforces, as its message and the README
# name them.
for file in installer/module.yaml docs/README.md; do
    for gib in "$CORE_GIB" "$DESKTOP_GIB"; do
        expect "${file} names ${gib} GiB" "$(holds grep -qF "${gib} GiB" "$file")" yes
    done
done

# ─── The mirrors ─────────────────────────────────────────────────────────────

# A listed name goes as its code, a typed one as typed.
while read -r answer want; do
    expect "mirror_country for ${answer}" "$(ARCH_OS_REFLECTOR_COUNTRY="$answer" mirror_country)" "$want"
done <<'EOF'
Germany DE
Atlantis Atlantis
none
EOF

# ─── The firmware ────────────────────────────────────────────────────────────

# Four attribute bytes, then the value. - for a firmware without the variable.
EFIVARS="${templates}/efivars"
mkdir -p "$EFIVARS"
while read -r value want; do
    rm -f "${EFIVARS}/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    [ "$value" = - ] || printf '\x06\x00\x00\x00%b' "\\x0${value}" >"${EFIVARS}/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    expect "secure_boot_off with SecureBoot ${value}" "$(holds secure_boot_off)" "$want"
done <<'EOF'
0 yes
1 no
- yes
EOF

# ─── Expected Failures ───────────────────────────────────────────────────────

# The runtime's rules for an action, first inside $(…): an ERR trap, no -e or -u.
# The exit status is the output.
as_action() {
    set +eu -E
    trap 'exit $?' ERR
    trap 'echo $?' EXIT
}

wifi_station() { echo wlan0; }
iwctl() { return "$joins"; }
wifi_online() { return "$online"; }
export ARCH_OS_WIFI_SSID=home ARCH_OS_WIFI_PASSPHRASE=x
while read -r joins online want; do
    expect "join_wifi_with_passphrase with iwctl ${joins} and wifi_online ${online}" \
        "$(as_action && join_wifi_with_passphrase)" "$want"
done <<'EOF'
0 0 0
1 0 10
0 1 10
EOF

# ─── EFI Partition ───────────────────────────────────────────────────────────

# mount falls back to read-only where the partition is mounted so elsewhere,
# unless -w asks for read-write.
fsck.fat() { :; }
mount() {
    [[ " $* " != *" -w "* ]] || {
        echo "mount: /mnt/boot: /dev/vda1 already mounted on /tmp/probe." >&2
        return 32
    }
}
expect "mount_esp where the EFI partition is mounted read-only elsewhere" \
    "$( (as_action && ARCH_OS_RECOVERY_DISK=/dev/vda mount_esp /mnt/boot) 2>&1 | paste -sd' ')" \
    "mount: /mnt/boot: /dev/vda1 already mounted on /tmp/probe. 32"

[ "$status" -eq 0 ] && echo "lib.sh passes every case"
exit "$status"
