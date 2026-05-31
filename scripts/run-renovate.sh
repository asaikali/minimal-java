#!/usr/bin/env bash
#
# Dispatch the remote Renovate workflow (.github/workflows/renovate.yml) on
# GitHub now and tail its logs. Useful after ticking a checkbox on the Dependency
# Dashboard issue — Renovate only reads checkbox state at the start of a run, so a
# click does nothing until the next dispatch (or the daily 01:00 UTC scheduled
# run). Also handy after merging a PR that conflicts with other open Renovate PRs,
# to force their rebases now rather than at 01:00 UTC.
#
#   run-renovate.sh
#
# Requires the gh CLI, authenticated against this repo (gh auth login).
#
set -Eeuo pipefail

command -v gh >/dev/null 2>&1 || { echo "required command 'gh' not found" >&2; exit 1; }

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
echo "dispatching renovate.yml on ${repo} (ref=main)"
gh workflow run renovate.yml --ref main

# Wait for GitHub to register the dispatch, then grab the most recent
# workflow_dispatch run. Filtering by --event avoids picking up a scheduled run
# that happened to fire moments before this script.
sleep 5
run_id=$(gh run list \
    --workflow=renovate.yml \
    --branch=main \
    --event=workflow_dispatch \
    --limit=1 \
    --json databaseId \
    --jq '.[0].databaseId')

echo "watching run ${run_id} (Ctrl-C to detach; the run keeps running on GitHub)"
gh run watch "${run_id}" --exit-status
