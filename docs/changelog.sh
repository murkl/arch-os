#!/usr/bin/env sh
# The entries a release is published with, read out of the changelog rather than
# typed a second time onto a release page.
#
#   changelog.sh <file>              every heading reads "## X.Y.Z - YYYY-MM-DD"
#   changelog.sh <file> <version>    ...and that version's entries, printed
#
# The second form is what a release page is made of, so a version nobody wrote
# an entry for stops the release instead of reaching the page as a bare heading.
#
# POSIX sh, and the same file in every project that keeps a changelog this way.
set -eu

[ "$#" -ge 1 ] || {
    echo "usage: $0 <file> [version]" >&2
    exit 1
}

file="$1"
version="${2:-}"

awk -v want="$version" '
    # Descending, which is what lets the top of the file be read as the version
    # being worked towards - by whoever opens it, and by changelog-warn.sh.
    function older(a, b,   x, y, i) {
        split(a, x, "."); split(b, y, ".")
        for (i = 1; i <= 3; i++)
            if (x[i] + 0 != y[i] + 0) return x[i] + 0 < y[i] + 0
        return 0
    }

    /^## / {
        if ($0 !~ /^## [0-9]+\.[0-9]+\.[0-9]+ - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
            print FILENAME ":" FNR ": a version heading reads \"## X.Y.Z - YYYY-MM-DD\"" > "/dev/stderr"
            bad = 1
        } else if (above != "" && !older($2, above)) {
            print FILENAME ":" FNR ": " $2 " under " above " - newest first, and no version twice" > "/dev/stderr"
            bad = 1
        } else {
            above = $2
        }
        if (versions++ == 0) newest = $2
        taking = (want != "" && $2 == want)
        if (taking) found = 1
        next
    }
    # Held rather than printed as it is read: nothing reaches a release page
    # before the checks below have passed. The blank lines around a section
    # belong to the file rather than to what the release says, so they are
    # dropped and the ones inside it kept.
    taking && NF == 0 { gap = 1; next }
    taking {
        if (entries++ && gap) section = section "\n"
        gap = 0
        section = section $0 "\n"
    }
    END {
        if (bad) exit 1
        if (versions == 0) {
            print FILENAME " holds no version at all" > "/dev/stderr"
            exit 1
        }
        if (want == "") exit 0
        if (!found) {
            print FILENAME " has no section for " want " - it opens on " newest > "/dev/stderr"
            exit 1
        }
        if (entries == 0) {
            print FILENAME " says nothing under " want > "/dev/stderr"
            exit 1
        }
        printf "%s", section
    }
' "$file"
