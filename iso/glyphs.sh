#!/bin/bash
# Every character that reaches the console, in the files given and in what the
# program draws itself, against the fonts font.sh builds. See README.md.
#
#   glyphs.sh <arch-os> <file>...
set -eu

# Code points are counted, not bytes: under the C locale bash would hand back
# the first byte of a multi-byte character instead.
export LC_ALL=C.UTF-8

[ "$#" -ge 2 ] || {
    echo "usage: $0 <arch-os> <file>..." >&2
    exit 1
}

# Read before anything else is, so a program that cannot answer stops this here
# rather than letting every file pass against an empty list.
INTERFACE_GLYPHS="$("$1" glyphs)"
[ -n "$INTERFACE_GLYPHS" ] || {
    echo "Error: $1 glyphs named nothing" >&2
    exit 1
}
shift

# The fonts as the images get them. Not a cd, so the paths handed in stay the
# ones the caller named and the failures below point at files somebody can open.
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

    # What the font can draw, one code point per line. A slot may answer to
    # several of them, which is why this is read out of the table rather than
    # counted.
    mapped="$(gzip -cdf "$font" | psfgettable - | grep -oE 'U\+[0-9a-fA-F]+' | tr '[:upper:]' '[:lower:]' | sort -u)"

    while read -r character; do
        printf -v point 'u+%04x' "'${character}"
        grep -qxF "$point" <<<"$mapped" && continue
        echo "${point} ${character} is not in ${name} and would be a box on the console:" >&2
        # A module's text is fixed here, the interface's by changing the font.
        if grep -qF -- "$character" <<<"$INTERFACE_GLYPHS"; then
            echo "  the interface draws it - ${name} is the wrong font for this image" >&2
        fi
        grep -lF -- "$character" "$@" | sed 's/^/  /' >&2
        status=1
    done <<<"$characters"
done

[ "$status" -eq 0 ] && echo "every character reads on the console in $(basename -s .psf.gz "$FONTS"/*.psf.gz | tr '\n' ' ')"
exit "$status"
