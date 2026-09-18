#!/usr/bin/env sh
# The changelog falling behind the work, said as a warning rather than as a
# refusal: the points may be written any time up to the release, and a build is
# not the place to insist on the order they are written in. Two questions, and
# the first one decides which is worth asking:
#
#   Is a section open for the next release? The one at the top of the file is,
#   unless it already carries a tag of its own. If none is open, everything
#   committed since that release has nowhere to be written down.
#
#   Has this change written anything there? What counts as this change is
#   everything since main - on a branch the whole branch, on main the commit
#   that just landed - and the working tree with it, so a line written but not
#   yet committed is a line written.
#
#   changelog-warn.sh <file>
#
# Where there is nothing to compare against, there is nothing to say: no
# repository, no main, a clone of one commit. It says nothing and is quiet.
#
# POSIX sh, and the same file in every project that keeps a changelog this way.
set -eu

[ "$#" -eq 1 ] || {
    echo "usage: $0 <file>" >&2
    exit 1
}

file="$1"

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# A file with no version in it at all is what the reader beside this one
# refuses outright, and one refusal is enough.
newest="$(sed -n '/^## /{s/^## \([^ ]*\).*/\1/p;q;}' "$file" 2>/dev/null || true)"
[ -n "$newest" ] || exit 0

open=""
if ! git rev-parse -q --verify "refs/tags/v$newest" >/dev/null; then
    open="$newest"
fi

if [ -z "$open" ]; then
    # Everything on top of the last release goes out in the next one, and there
    # is no section for it to go into.
    landed="$(git rev-list --count "refs/tags/v$newest..HEAD" 2>/dev/null || echo 0)"
    [ "$landed" -gt 0 ] || exit 0

    if [ "$landed" -eq 1 ]; then
        what="1 commit"
    else
        what="$landed commits"
    fi
    said="$what since $newest and no section open for the next release - add one at the top of the file"
else
    main="$(git rev-parse -q --verify origin/main || git rev-parse -q --verify main)" || exit 0
    base="$(git merge-base "$main" HEAD 2>/dev/null)" || exit 0

    # On main itself the branch point is HEAD, which compares nothing. What
    # landed there last is the change to ask about.
    if [ "$base" = "$(git rev-parse HEAD)" ]; then
        base="$(git rev-parse -q --verify HEAD^)" || exit 0
    fi

    # What the commits changed, and failing that what is not committed yet -
    # which is also how the file being written for the first time counts.
    touched="$(git diff --name-only "$base" -- "$file")"
    [ -n "$touched" ] || touched="$(git status --porcelain -- "$file")"
    [ -z "$touched" ] || exit 0

    said="nothing under $open says what changed here - write it now, or before the release"
fi

# On a run the warning is an annotation, so it lands on the run and on the
# change rather than in the middle of a log nobody scrolls back through.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::warning file=%s,line=1::%s\n' "$file" "$said"
else
    printf '%s: %s\n' "$file" "$said" >&2
fi
