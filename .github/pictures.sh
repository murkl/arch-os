#!/usr/bin/env bash
# The pictures in docs/ for the open release pull request, pushed onto its
# branch: main as it is, at the version that pull request raises. The branch
# itself may sit on an older main, since a merge that releases nothing leaves
# it alone, so it gives the version and nothing else.
#
#   .github/pictures.sh <release branch>
#
# GH_TOKEN pushes, GITHUB_TOKEN fetches the runtime.
set -euo pipefail

branch="$1"

git fetch --depth=1 origin "$branch"
version="$(git show FETCH_HEAD:oak.yaml | sed -n 's/^version:[[:space:]]*//p')"
[ -n "$version" ] || {
    echo "oak.yaml on ${branch} names no version" >&2
    exit 1
}
sed -i "s/^version:.*/version: ${version}/" oak.yaml
make docs

release="$(mktemp -d)"
git worktree add --detach "$release" FETCH_HEAD
cp docs/banner.png "${release}/docs/"
cp docs/screenshots/*.png "${release}/docs/screenshots/"

cd "$release"
git add docs
if git diff --cached --quiet; then
    echo "The pictures on ${branch} are these already"
    exit 0
fi
git -c user.name='github-actions[bot]' \
    -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit -m "docs: the pictures at ${version}"

# The token reaches git through its environment, never its command line.
GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
    GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN:?}" | base64 -w0)" \
    git push origin "HEAD:${branch}"
