#!/usr/bin/env sh
# Stores the release token as secret RELEASE_TOKEN of the environment release,
# limited to main: a fine-grained personal access token with Contents and Pull
# requests read and write, pasted when gh asks. Needs gh with admin rights.
# Identical in every project released this way.
#
#   .github/release-token.sh
set -eu

gh api --silent -X PUT 'repos/{owner}/{repo}/environments/release' --input - <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
# An existing policy answers 303, which gh follows.
gh api --silent -X POST 'repos/{owner}/{repo}/environments/release/deployment-branch-policies' \
    -f name=main -f type=branch
gh secret set RELEASE_TOKEN --env release
