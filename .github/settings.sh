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

if [ -f "${dir}/code-scanning.json" ]; then
    gh api --silent -X PATCH 'repos/{owner}/{repo}/code-scanning/default-setup' --input "${dir}/code-scanning.json"
fi

# One ruleset called main, updated in place.
id="$(gh api 'repos/{owner}/{repo}/rulesets' --jq '.[] | select(.name == "main") | .id')"
if [ -n "$id" ]; then
    gh api --silent -X PUT "repos/{owner}/{repo}/rulesets/${id}" --input "${dir}/ruleset.json"
else
    gh api --silent -X POST 'repos/{owner}/{repo}/rulesets' --input "${dir}/ruleset.json"
fi
