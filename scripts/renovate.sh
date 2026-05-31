#!/usr/bin/env bash
#
# Preview what Renovate would do against the working tree, without touching
# GitHub. Uses renovate.json at the repo root for configuration and runs in
# --dry-run=full --platform=local mode, so it opens no PRs and changes no files.
# Useful for tuning renovate.json before committing.
#
#   renovate.sh                 # preview with renovate.json as-is
#   LOG_LEVEL=debug renovate.sh # more detail when a dependency isn't detected
#
# Requires Node.js (for npx). --onboarding=false skips the "Configure Renovate"
# PR flow that doesn't apply in local mode. The trailing summary lists every PR
# Renovate would open; ignore the "Error updating branch" warnings — those are
# the local platform's expected limitation, not real failures.
#
# We pin renovate@latest rather than a bare `npx renovate`: npx reuses any cached
# copy of a bare package name regardless of age, so a bare invocation can silently
# run a years-old Renovate that rejects current config (e.g. customManagers'
# managerFilePatterns). @latest keeps the local preview aligned with the modern
# Renovate the CI action runs. Override with RENOVATE_NPM_SPEC to match CI exactly.
#
# Note: no `set -e`. Renovate intentionally exits non-zero in --platform=local
# mode (it can't sync git locally), so aborting on that would skip the summary
# below. We keep -u/pipefail safety without dying on that expected exit.
set -uo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

LOG_FILE=$(mktemp -t renovate-dryrun.XXXXXX.log)

LOG_LEVEL=${LOG_LEVEL:-info} npx --yes "${RENOVATE_NPM_SPEC:-renovate@latest}" \
    --platform=local \
    --dry-run=full \
    --onboarding=false \
    "$@" 2>&1 | tee "${LOG_FILE}"

echo
echo "=== Updates Renovate would propose (each line = one PR) ==="
grep -oE 'branch=renovate/[a-zA-Z0-9._-]*' "${LOG_FILE}" | sort -u | sed 's|branch=renovate/||'
echo
echo "Full log: ${LOG_FILE}"
