#!/usr/bin/env bash
# The names this Installer hands to other programs, against those programs' own
# lists: the two lookup tables beside this file, and the packages its tasks
# install.
#
#   check.sh
#
# Every value in them is a name some other program has to recognise, and one it
# does not costs nothing to write: loadkeys, setfont and the desktop's keyboard
# configuration each fall back silently and leave the machine on a layout, a
# font or a clock nobody chose. Both tables say "Validate against: ..." in their
# own headers - this is that sentence, run.
#
# Keymaps are read off /usr/share/kbd/keymaps rather than out of localectl.
# They are the same table, since that is where localectl reads them; the files
# are the only one of the two that answers in a container, which is where this
# also runs.
#
# The language column is deliberately not checked against the locales the C
# library ships: an Arch container extracts almost none of them, so the check
# would pass there without having looked - and a check that is green where
# nothing could be read is worse than no check. A language nobody has spelled
# right falls back to the American layout, which is loud enough.
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
fonts="$(find /usr/share/kbd/consolefonts -name '*.psf*' -printf '%f\n' | sed 's/\.psfu\?\(\.gz\)\?$//' | sort -u)"
layouts="$(grep -v '^#' x11-layouts | awk 'NF { print $1 }' | sort -u)"

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
        complain "languages: ${language} names the layout ${layout}, which x11-layouts does not have"
    [ "$font" = none ] || grep -qxF "$font" <<<"$fonts" ||
        complain "languages: ${language} names the font ${font}, which setfont does not have"
done <languages

# The territory code a locale ends in, where the mirror list calls that country,
# and the time zone it keeps. A "-" for the country is a country Arch has no
# mirror in; the time zone is still of use.
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
        complain "countries: ${code} spells its country \"${country}\" - it is handed to reflector as it stands, so it is reflector's own spelling or a - where Arch has no mirror"
    [ -f "/usr/share/zoneinfo/${zone}" ] ||
        complain "countries: ${code} names the time zone ${zone}, which tzdata does not have"
done <countries

# Every package a task names outright, and every list answer that is one,
# against the repositories this system syncs: a name Arch dropped fails here
# rather than in somebody's installation. Names put together at run time are
# looked up by their task, which says so where one is missing.
tasks=../tasks
repos="$(pacman-conf --repo-list)"
packages="$(
    awk '
        { sub(/#.*/, "") }
        /(^|[[:space:]])(packages|lib32)\+?=\(/ { list = 1; sub(/.*(packages|lib32)\+?=\(/, "") }
        /chroot_pacman_install / { sub(/.*chroot_pacman_install /, ""); print; next }
        list { line = $0; if (sub(/\).*/, "", line)) list = 0; print line }
    ' "$tasks"/@*/*/task.sh
    awk '/^  - name: ARCH_OS_(EDITOR|BROWSER|BACKUP)$/ { want = 1 } want && /^    options:/ { gsub(/.*\[|\].*/, ""); print; want = 0 }' ../module.yaml
    sed -n 's/^export KERNEL=\(.*\)/\1 \1-headers/p; s/^[[:space:]]*echo \([a-z]*-ucode\)$/\1/p' ../../../oak.sh
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
