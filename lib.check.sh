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

# On the Recovery partition only a newer one. Elsewhere the newest, only if the
# disk's Recovery does not boot.
while read -r own starts running want; do
    MODULE_VERSION="$running"
    on_recovery_partition() { [ "$own" = yes ]; }
    recovery_starts() { [ "$starts" = yes ]; }
    expect "recovery_update on its partition: ${own}, starts: ${starts}, running ${running}" \
        "$(recovery_update <<<"$compact" | cut -d' ' -f1)" "$want"
done <<'EOF'
yes yes 2.0.0 2.1.0
yes yes 2.1.0-dev 2.1.0
yes yes 2.1.0
yes yes 2.1.1-dev
no yes 2.0.0
no no 2.0.0 2.1.0
no no 2.9.0-dev 2.1.0
no no 4.0.0
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

# The live system's keymap per case, - for none.
live_keymap() { [ "$live" = - ] || printf '%s' "$live"; }

while read -r live language want; do
    expect "prefill_keymap live ${live} language ${language}" "$(MODULE_LANGUAGE="$language" prefill_keymap)" "$want"
done <<'EOF'
- de de-latin1
- pt_BR br-abnt2
- xx us
fr-latin1 de fr-latin1
EOF

while read -r keymap locale want; do
    expect "auto_layout ${keymap} ${locale}" \
        "$(ARCH_OS_VCONSOLE_KEYMAP="$keymap" ARCH_OS_LOCALE_LANG="$locale" auto_layout)" "$want"
done <<'EOF'
de-latin1 de_DE de
de-latin1 en_US de
us de_DE us
us ar_EG ara
de_CH-latin1 de_CH ch
uk de_DE gb
ru en_US ru
amiga-de de_DE us
EOF

[ "$status" -eq 0 ] && echo "lib.sh passes every case"
exit "$status"
