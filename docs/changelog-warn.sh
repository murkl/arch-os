#!/usr/bin/env sh
# A change that leaves no line in the changelog, said as a warning rather than
# as a refusal: the points may be written any time up to the release, and a
# build is not the place to insist on the order they are written in.
#
#   changelog-warn.sh <file>
#
# What counts as this change is everything since main - on a branch the whole
# branch, on main the commit that just landed - and the working tree with it, so
# a line written but not yet committed is a line written.
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

main="$(git rev-parse -q --verify origin/main || git rev-parse -q --verify main)" || exit 0
base="$(git merge-base "$main" HEAD 2>/dev/null)" || exit 0

# On main itself the branch point is HEAD, which compares nothing. What landed
# there last is the change to ask about.
if [ "$base" = "$(git rev-parse HEAD)" ]; then
    base="$(git rev-parse -q --verify HEAD^)" || exit 0
fi

# What the commits changed, and failing that what is not committed yet - which
# is also how the file being written for the first time counts.
touched="$(git diff --name-only "$base" -- "$file")"
[ -n "$touched" ] || touched="$(git status --porcelain -- "$file")"
[ -z "$touched" ] || exit 0

# The version at the top of the file, and whether it has already gone out: an
# entry belongs under the release being worked towards, never under one that is
# already on a release page.
newest="$(sed -n '/^## /{s/^## \([^ ]*\).*/\1/p;q;}' "$file" 2>/dev/null || true)"
if [ -n "$newest" ] && ! git rev-parse -q --verify "refs/tags/v$newest" >/dev/null; then
    said="nothing under $newest says what changed here - write it now, or before the release"
else
    said="no section is open for the next release - open one at the top of the file"
fi

# On a run the warning is an annotation, so it lands on the run and on the
# change rather than in the middle of a log nobody scrolls back through.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::warning file=%s,line=1::%s\n' "$file" "$said"
else
    printf '%s: %s\n' "$file" "$said" >&2
fi
