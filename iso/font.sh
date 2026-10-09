#!/bin/bash
# The console font of both images: Terminus Bold, the one font in Arch that is
# bold and clean at every size and holds Latin with its accents, Greek and
# Cyrillic. It lacks the two half blocks a QR code is drawn from, so they go into
# the two slots of its table that nothing draws.
#
#   font.sh <out-dir>
#
# One font per size, named arch-os-<size>.psf.gz. The sizes are read out of the
# launcher that picks from them, so what is built and what is asked for cannot
# differ.
set -eu

# Bytes are bytes here, whatever the locale does with a high one.
export LC_ALL=C

[ "$#" -eq 1 ] || {
    echo "usage: $0 <out-dir>" >&2
    exit 1
}
OUT="$1"

LAUNCHER="$(dirname "$0")/src/usr/local/bin/arch-os"
SIZES="$(sed -n 's/^SIZES="\(.*\)"/\1/p' "$LAUNCHER")"
[ -n "$SIZES" ] || {
    echo "Error: ${LAUNCHER} names no font sizes" >&2
    exit 1
}

for tool in psfgettable psfaddtable; do
    command -v "$tool" >/dev/null || {
        echo "Error: ${tool} not found - install the kbd package" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

for size in $SIZES; do
    source="/usr/share/kbd/consolefonts/ter-v${size}b.psf.gz"
    [ -f "$source" ] || {
        echo "Error: no ${source} - install the terminus-font package" >&2
        exit 1
    }
    gzip -cd "$source" >"$WORK/font"
    psfgettable "$WORK/font" >"$WORK/table"

    # Where the glyphs start, how many bytes each takes, and its cell. PSF2 says
    # so in its header; PSF1, which the sizes 8 pixels wide come in, has a
    # header of 4 bytes and a byte a row.
    case "$(od -An -tx1 -N2 "$WORK/font" | tr -d ' ')" in
    72b5) read -r offset _ _ bytes height width < <(od -An -tu4 -w24 --endian=little -j8 -N24 "$WORK/font") ;;
    3604) offset=4 bytes="$(od -An -tu1 -j3 -N1 "$WORK/font" | tr -d ' ')" height="$bytes" width=8 ;;
    *)
        echo "Error: ${source} is no PSF font" >&2
        exit 1
        ;;
    esac
    # The launcher takes every size to be twice as tall as it is wide.
    [ "$height" -eq "$size" ] && [ "$((width * 2))" -eq "$size" ] || {
        echo "Error: ${source} is ${width} by ${height}, which the launcher reads as $((size / 2)) by ${size}" >&2
        exit 1
    }
    head -c "$((bytes / 2))" /dev/zero >"$WORK/empty"
    tr '\0' '\377' <"$WORK/empty" >"$WORK/solid"

    # The glyph of ╬ becomes ▀ and that of ╪ becomes ▄: the half that is set,
    # then the half that is not, or the other way round.
    for patch in 256c:2580:solid:empty 256a:2584:empty:solid; do
        IFS=: read -r old new first second <<<"$patch"
        slot="$(awk -v old="U+${old}" 'NF == 2 && $2 == old { print $1 }' "$WORK/table")"
        [ -n "$slot" ] || {
            echo "Error: ${source} holds no slot for U+${old} alone, which this takes for U+${new}" >&2
            exit 1
        }
        cat "$WORK/$first" "$WORK/$second" |
            dd of="$WORK/font" bs=1 seek="$((offset + slot * bytes))" conv=notrunc status=none
        awk -v slot="$slot" -v new="U+${new}" 'BEGIN { OFS = "\t" } $1 == slot { $2 = new } { print }' \
            "$WORK/table" >"$WORK/table.new"
        mv "$WORK/table.new" "$WORK/table"
    done

    psfaddtable "$WORK/font" "$WORK/table" "$WORK/font.new"
    for point in 'U+2580' 'U+2584'; do
        psfgettable "$WORK/font.new" | grep -q "$point" || {
            echo "Error: arch-os-${size} has no ${point} after all" >&2
            exit 1
        }
    done
    gzip -9 -n -c "$WORK/font.new" >"${OUT}/arch-os-${size}.psf.gz"
done
