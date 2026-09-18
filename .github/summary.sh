#!/usr/bin/env sh
# Puts the files a job produced on the run's summary page, so what a run made is
# read where the run is read rather than out of the log.
#
#   summary.sh <heading> <file>...
#
# The checksum is read off each file rather than out of a file beside it: a
# build writes none, and what a download is checked against is the digest
# GitHub publishes for the asset once the file is on a release.
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
        printf "| \`%s\` | %s | \`%s\` |\n" \
            "$(basename "$file")" \
            "$(LC_ALL=C numfmt --to=iec --suffix=B "$(stat -c%s "$file")")" \
            "$(sha256sum "$file" | cut -d' ' -f1)"
    done
    printf '\nDownload it from the artefacts listed on this run.\n\n'
} >>"$GITHUB_STEP_SUMMARY"
