#!/usr/bin/env bash
# The functions of oak.sh that decide from what they are handed, against
# answers written out here. What they read off a machine is for the tests
# beside each task, run on that machine.
#
#   oak.check.sh
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=oak.sh
source ./oak.sh

status=0
expect() {
    if [ "$2" != "$3" ]; then
        printf '%s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3" >&2
        status=1
    fi
}

# A command's answer as yes or no.
holds() { if "$@"; then echo yes; else echo no; fi; }

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

# A list as GitHub sends it, field for field in its order, newest first: one
# for another series, a pre-release, one published before GitHub kept a
# checksum, and a label and a body that hold what the patterns look for.
asset() {
    printf '{"url":"https://api.github.com/repos/murkl/arch-os/releases/assets/%s","id":%s,"name":"%s","label":"%s","uploader":{"url":"https://api.github.com/users/murkl"},"size":1,"digest":%s,"browser_download_url":"https://github.com/murkl/arch-os/releases/download/v%s/%s"}' \
        "$1" "$1" "$3" "${5:-}" "$4" "$2" "$3"
}
release() {
    local version="$1"
    shift
    printf '{"url":"https://api.github.com/repos/murkl/arch-os/releases/%s","assets_url":"https://api.github.com/repos/murkl/arch-os/releases/%s/assets","tag_name":"v%s","draft":false,"prerelease":%s,"assets":[%s],"tarball_url":"https://api.github.com/repos/murkl/arch-os/tarball/v%s","body":"%s"}' \
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

# The same, laid out the way a person reads it, a space after every colon.
pretty="$(sed -e 's/":/": /g' -e 's/,"/,\n  "/g' -e 's/{/{\n  /g' -e 's/}/\n}/g' <<<"$compact")"

recovery() { printf 'https://github.com/murkl/arch-os/releases/download/v%s/arch-os-%s-recovery-x86_64.tar' "$1" "$1"; }

for layout in compact pretty; do
    json="$compact"
    [ "$layout" = compact ] || json="$pretty"

    expect "asset_in .iso, ${layout}" "$(asset_in .iso <<<"$json")" \
        "https://github.com/murkl/arch-os/releases/download/v2.1.0/arch-os-2.1.0-x86_64.iso 211"
    expect "asset_in -recovery-x86_64.tar, ${layout}" "$(asset_in -recovery-x86_64.tar <<<"$json" | cut -d' ' -f2 | paste -sd' ')" \
        "30 22 212  200"
    expect "asset_in .zip, ${layout}" "$(asset_in .zip <<<"$json")" ""

    while read -r running want; do
        release_version() { echo "$running"; }
        expect "newest_recovery for ${running}, ${layout}" "$(newest_recovery <<<"$json")" "$want"
    done <<EOF
2.0.0 2.1.0 $(recovery 2.1.0) 212
2.5.0 2.1.0 $(recovery 2.1.0) 212
3.0.0-dev 3.0.0 $(recovery 3.0.0) 30
4.0.0
EOF
done

# On its own partition, only what is newer. From anywhere else, only for a
# Recovery that does not start, and then whatever is newest.
while read -r own starts running want; do
    release_version() { echo "$running"; }
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

expect "render fills and leaves every \$" "$(render "${templates}/plain" NAME=tux | od -c)" \
    "$(sed 's/{{NAME}}/tux/' "${templates}/plain" | od -c)"
expect "render writes a value holding {{ as it is" "$(render "${templates}/two" NAME='{{OTHER}}' OTHER=x)" "{{OTHER}} and x"
expect "render with a placeholder nobody fills" "$(holds render "${templates}/two" NAME=x 2>/dev/null)" no
expect "render with a value nothing asks for" "$(holds render "${templates}/plain" NAME=x EXTRA=y 2>/dev/null)" no
expect "render with a {{ that opens nothing" "$(holds render "${templates}/open" 2>/dev/null)" no
expect "render with a name that is no NAME" "$(holds render "${templates}/lower" lower=x 2>/dev/null)" no
expect "render with no template" "$(holds render "${templates}/none" 2>/dev/null)" no

# ─── The disk ────────────────────────────────────────────────────────────────

while read -r disk number want; do
    expect "part_of ${disk} ${number}" "$(part_of "$disk" "$number")" "$want"
done <<'EOF'
/dev/sda 2 /dev/sda2
/dev/vda 3 /dev/vda3
/dev/nvme0n1 1 /dev/nvme0n1p1
/dev/mmcblk0 3 /dev/mmcblk0p3
EOF

[ "$status" -eq 0 ] && echo "oak.sh decides as written down here"
exit "$status"
