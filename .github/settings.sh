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
# POSIX sh: this is a handful of calls, not a program.
set -eu

command -v gh >/dev/null || {
    echo "gh is not installed - pacman -S github-cli, then gh auth login" >&2
    exit 1
}

dir="$(dirname "$0")/settings"

# How a pull request is merged: squashed under its title alone, which is the
# line a version is read out of. A body would be read too, and every line in it
# that opens on `feat:` or `fix:` would be one more entry in the changelog. Its
# branch deleted afterwards, and merged on its own once the checks main asks for
# have passed, where somebody asked for that.
gh api --silent -X PATCH 'repos/{owner}/{repo}' --input "${dir}/repository.json"

# What a workflow's own token may do unless the workflow says otherwise: read,
# and open the release pull request.
gh api --silent -X PUT 'repos/{owner}/{repo}/actions/permissions/workflow' --input "${dir}/actions.json"

# CodeQL's default setup, for the languages code-scanning.json names: those no
# check in the Makefile reads already.
gh api --silent -X PATCH 'repos/{owner}/{repo}/code-scanning/default-setup' --input "${dir}/code-scanning.json"

# What main is held to. Updated where it exists already, so it stays one ruleset
# rather than one more per run.
id="$(gh api 'repos/{owner}/{repo}/rulesets' --jq '.[] | select(.name == "main") | .id')"
if [ -n "$id" ]; then
    gh api --silent -X PUT "repos/{owner}/{repo}/rulesets/${id}" --input "${dir}/ruleset.json"
else
    gh api --silent -X POST 'repos/{owner}/{repo}/rulesets' --input "${dir}/ruleset.json"
fi

# The ruleset is the one protection: a classic one beside it is a second truth
# nobody declares. A 404 says there is none.
branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
if ! out="$(gh api --silent -X DELETE "repos/{owner}/{repo}/branches/${branch}/protection" 2>&1)"; then
    case "$out" in
    *"HTTP 404"*) ;;
    *)
        echo "$out" >&2
        exit 1
        ;;
    esac
fi

echo "applied to $(gh repo view --json nameWithOwner --jq .nameWithOwner): .github/settings/"
