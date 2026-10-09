#!/bin/bash
# Every character that reaches the virtual console, against the fonts this image
# loads before the interface draws on it.
#
#   glyphs.sh <oak> <file>...
#
# A Linux console has one font and that font has a fixed table of glyphs, so a
# character outside it is a box on the screen - in whichever language it happens
# to be in, which is not the one whoever wrote it reads. The fonts are built by
# font.sh, as the images build them, so what is read is what ships.
#
# Two things reach that console and only one of them is in the files handed in.
# The other is Oak's own interface, which is compiled into the binary, so the
# binary is asked what it draws there rather than a copy of that being kept here.
#
#   https://github.com/murkl/oak/blob/main/docs/REFERENCE.md#translations
set -eu

# Code points are counted, not bytes: under the C locale bash would hand back
# the first byte of a multi-byte character instead.
export LC_ALL=C.UTF-8

[ "$#" -ge 2 ] || {
    echo "usage: $0 <oak> <file>..." >&2
    exit 1
}

# Read before anything else is, so a runtime that cannot answer stops this here
# rather than letting every file pass against an empty list.
INTERFACE_GLYPHS="$("$1" --glyphs)"
[ -n "$INTERFACE_GLYPHS" ] || {
    echo "Error: $1 --glyphs named nothing" >&2
    exit 1
}
shift

# The fonts as the images get them. Not a cd, so the paths handed in stay the
# ones the caller named and the failures below point at files somebody can open.
FONTS="$(mktemp -d)"
trap 'rm -rf "$FONTS"' EXIT
"$(dirname "$0")/font.sh" "$FONTS"

command -v psfgettable >/dev/null || {
    echo "Error: psfgettable not found - install the kbd package" >&2
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
        # Where it came from: the files that hold it, or the interface itself,
        # which has none. Named either way, because the two are fixed in
        # different places - a module's text is rewritten here, the font is what
        # has to change for the interface.
        if grep -qF -- "$character" <<<"$INTERFACE_GLYPHS"; then
            echo "  the interface draws it - ${name} is the wrong font for this image" >&2
        fi
        grep -lF -- "$character" "$@" | sed 's/^/  /' >&2
        status=1
    done <<<"$characters"
done

[ "$status" -eq 0 ] && echo "every character reads on the console in $(basename -s .psf.gz "$FONTS"/*.psf.gz | tr '\n' ' ')"
exit "$status"
