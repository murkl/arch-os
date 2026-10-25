#!/usr/bin/env sh
# Applies .github/settings/ to this repository on GitHub, as an admin logged in
# with gh. Every call sets a whole state, so a rerun changes nothing. The same
# file in every project released this way.
#
#   .github/settings.sh
set -eu

dir="$(dirname "$0")/settings"

gh api --silent -X PATCH 'repos/{owner}/{repo}' --input "${dir}/repository.json"
gh api --silent -X PUT 'repos/{owner}/{repo}/actions/permissions/workflow' --input "${dir}/actions.json"

# Alerts on vulnerable dependencies, and a private way to report a vulnerability.
gh api --silent -X PUT 'repos/{owner}/{repo}/vulnerability-alerts'
gh api --silent -X PUT 'repos/{owner}/{repo}/private-vulnerability-reporting'

if [ -f "${dir}/topics.json" ]; then
    gh api --silent -X PUT 'repos/{owner}/{repo}/topics' --input "${dir}/topics.json"
fi

if [ -f "${dir}/code-scanning.json" ]; then
    gh api --silent -X PATCH 'repos/{owner}/{repo}/code-scanning/default-setup' --input "${dir}/code-scanning.json"
fi

# Every ruleset-*.json, found by the name it carries and updated in place.
for file in "${dir}"/ruleset-*.json; do
    name="$(sed -n 's/^  "name": "\(.*\)",$/\1/p' "$file")"
    [ -n "$name" ] || {
        echo "settings.sh: ${file} carries no name" >&2
        exit 1
    }
    id="$(gh api 'repos/{owner}/{repo}/rulesets' --jq ".[] | select(.name == \"${name}\") | .id")"
    if [ -n "$id" ]; then
        gh api --silent -X PUT "repos/{owner}/{repo}/rulesets/${id}" --input "$file"
    else
        gh api --silent -X POST 'repos/{owner}/{repo}/rulesets' --input "$file"
    fi
done
