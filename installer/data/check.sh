#!/usr/bin/env bash
# The names the Installer hands to other programs, against those programs' own
# lists: loadkeys, setfont and xkb fall back silently on a name they lack.
#
#   check.sh
#
# Keymaps and layouts come from kbd's and xkb's own files, which a container
# has where localectl does not answer. Languages are not checked against glibc's locales,
# which an Arch container leaves out, so that check would pass unread.
set -euo pipefail

# Byte comparison and A-Z meaning A-Z: a country is spelled the way reflector
# spells it, and Réunion and Türkiye are spelled with letters a range in some
# other collation would swallow.
export LC_ALL=C

cd "$(dirname "$0")"

status=0
complain() {
    echo "$1" >&2
    status=1
}

keymaps="$(find /usr/share/kbd/keymaps -name '*.map.gz' -printf '%f\n' | sed 's/\.map\.gz$//' | sort -u)"
# kbd's own, the fonts an installation has, as options_fonts lists them.
fonts="$(pacman -Qlq kbd | sed -n 's|^/usr/share/kbd/consolefonts/\([^/]*\)\.psfu\{0,1\}\(\.gz\)\{0,1\}$|\1|p' | sort -u)"
layouts="$(awk '/^! / { inside = ($0 == "! layout"); next } inside && NF { print $1 }' /usr/share/X11/xkb/rules/base.lst | sort -u)"

# language, the keyboard it is typed on in two spellings, and the font the
# console draws it in.
seen=""
while read -r language keymap layout font extra; do
    case "$language" in '' | \#*) continue ;; esac

    if [ -z "$font" ] || [ -n "$extra" ]; then
        complain "languages: ${language} is not four columns"
        continue
    fi

    grep -qxF "$language" <<<"$seen" && complain "languages: ${language} stands there twice"
    seen="${seen}${language}"$'\n'

    grep -qxF "$keymap" <<<"$keymaps" ||
        complain "languages: ${language} names the keymap ${keymap}, which loadkeys does not have"
    grep -qxF "$layout" <<<"$layouts" ||
        complain "languages: ${language} names the layout ${layout}, which xkb does not have"
    [ "$font" = none ] || grep -qxF "$font" <<<"$fonts" ||
        complain "languages: ${language} names the font ${font}, which setfont does not have"
done <languages

# The territory code a locale ends in, where the mirror list calls that country,
# and the time zone it keeps. A "-" for the country is a country Arch has no
# mirror in, the time zone is still of use.
seen=""
while IFS=$'\t' read -r code country zone extra; do
    case "$code" in '' | \#*) continue ;; esac

    if [ -z "$zone" ] || [ -n "$extra" ]; then
        complain "countries: ${code} is not three columns, separated by tabs"
        continue
    fi

    grep -qxF "$code" <<<"$seen" && complain "countries: ${code} stands there twice"
    seen="${seen}${code}"$'\n'

    [[ "$code" =~ ^[A-Z][A-Z]$ ]] ||
        complain "countries: ${code} is not a two-letter territory code"
    [[ "$country" = "-" || "$country" =~ ^[A-Z] ]] ||
        complain "countries: ${code} spells its country \"${country}\": reflector takes it as it stands, so it is reflector's own spelling, or - where Arch has no mirror"
    [ -f "/usr/share/zoneinfo/${zone}" ] ||
        complain "countries: ${code} names the time zone ${zone}, which tzdata does not have"
done <countries

# Every package a task names outright, against the repositories: a name Arch
# dropped fails here, not in an installation. Names built at run time are their
# task's to look up.
tasks=../tasks
repos="$(pacman-conf --repo-list)"
packages="$(
    awk '
        { sub(/#.*/, "") }
        /(^|[[:space:]])(packages|lib32)\+?=\(/ { list = 1; sub(/.*(packages|lib32)\+?=\(/, "") }
        /chroot_pacman_install / { sub(/.*chroot_pacman_install /, ""); print; next }
        list { line = $0; if (sub(/\).*/, "", line)) list = 0; print line }
    ' "$tasks"/*/task.sh
    awk '/^ *- name: ARCH_OS_(EDITOR|BROWSER|BACKUP)$/ { want = 1 } want && /^ *options:/ { gsub(/.*\[|\].*/, ""); print; want = 0 }' ../module.yaml
    sed -n 's/^export KERNEL=\(.*\)/\1 \1-headers/p; s/^[[:space:]]*echo \([a-z]*-ucode\)$/\1/p' ../../lib.sh
)"
packages="$(tr ', ' '\n' <<<"$packages" | grep -E '^[a-z0-9][a-z0-9@._+-]*$' | grep -vx none | sort -u)"
if ! grep -qx multilib <<<"$repos"; then
    echo "packages: multilib is not synced here, so $(grep -c '^lib32-' <<<"$packages") lib32 names went unchecked"
    packages="$(grep -v '^lib32-' <<<"$packages")"
fi
mapfile -t names <<<"$packages"
if ! said="$(pacman -Sp --print-format %n "${names[@]}" 2>&1 >/dev/null)"; then
    missing="$(sed -n 's/^error: target not found: //p' <<<"$said")"
    [ -n "$missing" ] || complain "packages: pacman could not be asked - ${said}"
    while read -r name; do
        [ -z "$name" ] || complain "packages: ${name} is in no repository this system syncs"
    done <<<"$missing"
fi

[ "$status" -eq 0 ] && echo "every name in languages and countries is one this system has, and $(wc -l <<<"$packages") packages are in the repositories"
exit "$status"
