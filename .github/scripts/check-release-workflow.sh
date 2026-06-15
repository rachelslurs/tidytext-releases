#!/usr/bin/env bash
# Structural hardening gate for the release pipeline. PURE TEXT PARSE — no secrets — so it runs
# safely on every PR (incl. forks) and can be a required status check. It verifies the workflows
# STAY hardened; it does NOT verify secret/PAT access (that needs the gated `release` environment —
# see the "Release preflight (config doctor)" workflow).
set -euo pipefail

# Operate from the repo root regardless of how we're invoked (CI runs from root; local from anywhere).
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

REL=.github/workflows/release.yml
fail() {
  echo "::error::$*"
  exit 1
}
[ -f "$REL" ] || fail "missing $REL"

shopt -s nullglob
WORKFLOWS=(.github/workflows/*.yml .github/workflows/*.yaml)

# 1. Every `uses:` in every workflow is pinned to a full 40-hex commit SHA (no floating tags).
for wf in "${WORKFLOWS[@]}"; do
  if grep -nE '^[[:space:]]*-?[[:space:]]*uses:' "$wf" | grep -vE '@[0-9a-f]{40}([[:space:]]|#|$)'; then
    fail "$wf: an action above is not pinned to a 40-hex commit SHA"
  fi
done

# 2. No workflow names the private source repo — it must be reached via the SOURCE_REPO secret.
if grep -nE 'tidytext\.cc' "${WORKFLOWS[@]}"; then
  fail "a workflow above names the private repo literally — use the SOURCE_REPO secret instead"
fi

# 3. The release workflow has no pull_request trigger (a secret-bearing job must never run on a PR).
#    Match a trigger KEY (e.g. `  pull_request:`), not the word inside a comment.
if grep -qE '^[[:space:]]*pull_request(_target)?:' "$REL"; then
  fail "$REL must not have a pull_request/pull_request_target trigger"
fi

# 4. Top-level permissions default to read-only (the build job elevates to contents: write itself).
grep -qE '^permissions:' "$REL" || fail "$REL has no top-level permissions: block"
TOP_PERM="$(awk '/^permissions:/{getline; print; exit}' "$REL" | tr -d '[:space:]')"
[ "$TOP_PERM" = "contents:read" ] || fail "$REL top-level permissions must be 'contents: read' (got '${TOP_PERM:-empty}')"

# 5. The build is gated on the protected `release` environment.
grep -qE '^[[:space:]]+environment:[[:space:]]*release([[:space:]]|$)' "$REL" \
  || fail "$REL must declare 'environment: release' on the build job"

# 6. harden-runner locks egress BEFORE any code is fetched (first, ahead of checkout).
HR_LINE="$(grep -nE 'step-security/harden-runner@' "$REL" | head -1 | cut -d: -f1)"
CO_LINE="$(grep -nE 'actions/checkout@' "$REL" | head -1 | cut -d: -f1)"
[ -n "$HR_LINE" ] || fail "$REL must run step-security/harden-runner"
{ [ -n "$CO_LINE" ] && [ "$HR_LINE" -lt "$CO_LINE" ]; } \
  || fail "$REL must run harden-runner before actions/checkout"

echo "✓ release pipeline structural hardening checks passed"
