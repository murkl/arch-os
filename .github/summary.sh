#!/usr/bin/env sh
# Puts the files a job produced on the run's summary page, so what a run made is
# read where the run is read rather than out of the log.
#
#   summary.sh <heading> <file>...
#
# Every file is expected to have a .sha256 beside it - which is what a build
# writes anyway, and what a download is checked against.
#
# POSIX sh, like get.sh: this is one table, not a program.
set -eu

[ "$#" -ge 2 ] || {
    echo "usage: $0 <heading> <file>..." >&2
    exit 1
}
[ -n "${GITHUB_STEP_SUMMARY:-}" ] || {
    echo "GITHUB_STEP_SUMMARY is not set - this runs in a workflow" >&2
    exit 1
}

heading="$1"
shift

{
    printf '## %s\n\n' "$heading"
    printf '| Artefact | Size | SHA-256 |\n'
    printf '| --- | ---: | --- |\n'
    for file in "$@"; do
        [ -f "$file" ] || continue
        if [ -f "${file}.sha256" ]; then
            checksum="$(cut -d' ' -f1 "${file}.sha256")"
        else
            checksum="none"
        fi
        printf "| \`%s\` | %s | \`%s\` |\n" \
            "$(basename "$file")" \
            "$(LC_ALL=C numfmt --to=iec --suffix=B "$(stat -c%s "$file")")" \
            "$checksum"
    done
    printf '\nDownload it from the artefacts listed on this run.\n\n'
} >>"$GITHUB_STEP_SUMMARY"
