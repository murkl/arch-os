#!/bin/bash
# Every character that reaches the virtual console, against the font this image
# loads before the interface draws on it.
#
#   glyphs.sh <file>...
#
# A Linux console has one font and that font has a fixed table of glyphs, so a
# character outside it is a box on the screen - in whichever language it happens
# to be in, which is not the one whoever wrote it reads. The font is read out of
# the launcher that loads it, so the two cannot come to name different ones.
#
# Two things reach that console and only one of them is in the files handed in.
# The other is Oak's own interface, which is compiled into the binary and has no
# file here to read it out of, so the marks it draws are spelled out below -
# identically to the set its own suite holds itself to, with the reason stated
# there:
#
#   https://github.com/murkl/oak/blob/main/docs/REFERENCE.md#translations
set -eu

# What the interface draws on a console: the frame, the rules and the scrollbar,
# the cursor and the marks a row carries, the shades a letter fades in through,
# and the three cells a picture is built from - the code on the welcome page and
# the mark over a finished run. ASCII is left out; every font has it.
INTERFACE_GLYPHS='─│┌┐└┘░▒█▀▄·•»↑↓'

# Code points are counted, not bytes: under the C locale bash would hand back
# the first byte of a multi-byte character instead.
export LC_ALL=C.UTF-8

[ "$#" -ge 1 ] || {
    echo "usage: $0 <file>..." >&2
    exit 1
}

# Not a cd, so the paths handed in stay the ones the caller named and the
# failures below point at files somebody can open.
LAUNCHER="$(dirname "$0")/src/usr/local/bin/arch-os"
FONT="$(sed -n 's/^setfont \([^ ]*\).*/\1/p' "$LAUNCHER")"
[ -n "$FONT" ] || {
    echo "Error: ${LAUNCHER} loads no console font for this to check against" >&2
    exit 1
}

command -v psfgettable >/dev/null || {
    echo "Error: psfgettable not found - install the kbd package" >&2
    exit 1
}

FONT_FILE="$(find /usr/share/kbd/consolefonts -name "${FONT}.psf*" -print -quit)"
[ -n "$FONT_FILE" ] || {
    echo "Error: no console font called ${FONT} on this machine - install the kbd package" >&2
    exit 1
}

# What the font can draw, one code point per line. A slot may answer to several
# of them, which is why this is read out of the table rather than counted.
mapped="$(gzip -cdf "$FONT_FILE" | psfgettable - | grep -oE 'U\+[0-9a-fA-F]+' | tr '[:upper:]' '[:lower:]' | sort -u)"

status=0
while read -r character; do
    printf -v point 'u+%04x' "'${character}"
    grep -qxF "$point" <<<"$mapped" && continue
    echo "${point} ${character} is not in ${FONT} and would be a box on the console:" >&2
    # Where it came from: the files that hold it, or the interface itself, which
    # has none. Named either way, because the two are fixed in different places -
    # a module's text is rewritten here, the font is what has to change for the
    # interface.
    if grep -qF -- "$character" <<<"$INTERFACE_GLYPHS"; then
        echo "  the interface draws it - ${FONT} is the wrong font for this image" >&2
    fi
    grep -lF -- "$character" "$@" | sed 's/^/  /' >&2
    status=1
done < <(grep -hoP '[^\x00-\x7F]' "$@" <(printf '%s\n' "$INTERFACE_GLYPHS") | sort -u)

[ "$status" -eq 0 ] && echo "every character reads on the console in ${FONT}"
exit "$status"
