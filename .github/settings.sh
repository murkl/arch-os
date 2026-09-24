#!/usr/bin/env sh
# The repository's settings on GitHub, applied out of the files in settings/
# beside this one rather than clicked: a repository set up again from scratch
# gets them from here, and changing one is a change under review like any other.
#
#   settings.sh
#
# Runs as whoever gh is logged in as, which has to be an admin of the
# repository. Every call sets a whole state, so running it again changes
# nothing. The same file in every project that is released this way.
#
# POSIX sh: this is three calls, not a program.
set -eu

command -v gh >/dev/null || {
    echo "gh is not installed - pacman -S github-cli, then gh auth login" >&2
    exit 1
}

dir="$(dirname "$0")/settings"

# How a pull request is merged: squashed under its own title and body, which is
# the line a version is read out of; its branch deleted afterwards; and merged
# on its own once the checks main asks for have passed, where somebody asked
# for that.
gh api --silent -X PATCH 'repos/{owner}/{repo}' --input "${dir}/repository.json"

# What a workflow's own token may do unless the workflow says otherwise: read,
# and open the release pull request.
gh api --silent -X PUT 'repos/{owner}/{repo}/actions/permissions/workflow' --input "${dir}/actions.json"

# What main is held to. Updated where it exists already, so it stays one ruleset
# rather than one more per run.
id="$(gh api 'repos/{owner}/{repo}/rulesets' --jq '.[] | select(.name == "main") | .id')"
if [ -n "$id" ]; then
    gh api --silent -X PUT "repos/{owner}/{repo}/rulesets/${id}" --input "${dir}/ruleset.json"
else
    gh api --silent -X POST 'repos/{owner}/{repo}/rulesets' --input "${dir}/ruleset.json"
fi

echo "applied to $(gh repo view --json nameWithOwner --jq .nameWithOwner): .github/settings/"
