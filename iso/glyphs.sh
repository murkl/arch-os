#!/bin/bash
# Checks every character that reaches the console, in the files given and in
# what the program draws itself, against the fonts font.sh builds. See
# README.md.
#
#   glyphs.sh <arch-os> <file>...
set -eu

# Code points, not bytes: under the C locale bash yields the first byte of a
# multi-byte character.
export LC_ALL=C.UTF-8

[ "$#" -ge 2 ] || {
    echo "usage: $0 <arch-os> <file>..." >&2
    exit 1
}

# Read first, so a program that cannot answer fails here instead of every file
# passing against an empty list.
INTERFACE_GLYPHS="$("$1" glyphs)"
[ -n "$INTERFACE_GLYPHS" ] || {
    echo "Error: $1 glyphs named nothing" >&2
    exit 1
}
shift

# The fonts as the images get them. No cd, so failures name the paths as given.
FONTS="$(mktemp -d)"
trap 'rm -rf "$FONTS"' EXIT
"$(dirname "$0")/font.sh" "$FONTS"

command -v psfgettable >/dev/null || {
    echo "Error: psfgettable not found: install the kbd package" >&2
    exit 1
}

characters="$(grep -hoP '[^\x00-\x7F]' "$@" <(printf '%s\n' "$INTERFACE_GLYPHS") | sort -u || true)"

status=0
for font in "$FONTS"/*.psf.gz; do
    name="$(basename "$font" .psf.gz)"

    # Drawable code points, one per line, read from the table since a slot may
    # map several.
    mapped="$(gzip -cdf "$font" | psfgettable - | grep -oE 'U\+[0-9a-fA-F]+' | tr '[:upper:]' '[:lower:]' | sort -u)"

    while read -r character; do
        printf -v point 'u+%04x' "'${character}"
        grep -qxF "$point" <<<"$mapped" && continue
        echo "${point} ${character} is missing from ${name}, a box on the console:" >&2
        # Module text is fixed in its file, interface text by changing the font.
        if grep -qF -- "$character" <<<"$INTERFACE_GLYPHS"; then
            echo "  the interface draws it, so ${name} is the wrong font for this image" >&2
        fi
        grep -lF -- "$character" "$@" | sed 's/^/  /' >&2
        status=1
    done <<<"$characters"
done

[ "$status" -eq 0 ] && echo "every character is in $(basename -s .psf.gz "$FONTS"/*.psf.gz | tr '\n' ' ')"
exit "$status"
