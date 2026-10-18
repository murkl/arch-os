#!/usr/bin/env sh
# Keeps the account's release token as the secret RELEASE_TOKEN of the
# environment release, which main alone may use: a fine-grained personal access
# token with Contents and Pull requests set to read and write, pasted when gh
# asks. The same file in every project released this way. Needs gh with admin
# rights on the repository.
#
#   .github/release-token.sh
set -eu

gh api --silent -X PUT 'repos/{owner}/{repo}/environments/release' --input - <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
# One that exists already answers 303, and gh follows it there.
gh api --silent -X POST 'repos/{owner}/{repo}/environments/release/deployment-branch-policies' \
    -f name=main -f type=branch
gh secret set RELEASE_TOKEN --env release
