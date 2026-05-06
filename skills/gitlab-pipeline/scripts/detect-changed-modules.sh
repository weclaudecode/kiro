#!/usr/bin/env bash
# detect-changed-modules.sh
#
# Detect Terragrunt modules whose files changed in this MR and emit a
# space-separated list of paths suitable for `terragrunt run-all` with
# `--terragrunt-include-dir`.
#
# Usage:
#   ./detect-changed-modules.sh <terragrunt-root> [base-ref]
#
# Examples:
#   ./detect-changed-modules.sh live                                  # auto base from MR
#   ./detect-changed-modules.sh live origin/main                      # explicit base
#
# In .gitlab-ci.yml:
#   script:
#     - CHANGED=$(./scripts/detect-changed-modules.sh live)
#     - cd live
#     - for d in $CHANGED; do terragrunt plan --terragrunt-include-dir="$d"; done

set -euo pipefail

TG_ROOT="${1:?Usage: $0 <terragrunt-root> [base-ref]}"
BASE_REF="${2:-}"

# Resolve the base ref. Prefer the GitLab MR target if available.
if [[ -z "${BASE_REF}" ]]; then
  if [[ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]]; then
    BASE_REF="${CI_MERGE_REQUEST_DIFF_BASE_SHA}"
  elif [[ -n "${CI_DEFAULT_BRANCH:-}" ]]; then
    BASE_REF="origin/${CI_DEFAULT_BRANCH}"
  else
    BASE_REF="origin/main"
  fi
fi

# Compute changed files vs the merge-base. `git diff A...B` uses the
# merge-base of A and B as the left side, which is what we want.
CHANGED_FILES=$(git diff --name-only "${BASE_REF}...HEAD" -- "${TG_ROOT}")

if [[ -z "${CHANGED_FILES}" ]]; then
  exit 0
fi

# For each changed file, walk up to the nearest dir containing
# terragrunt.hcl. De-duplicate.
declare -A SEEN=()
RESULT=()

while IFS= read -r f; do
  dir=$(dirname "$f")
  while [[ "$dir" != "." && "$dir" != "/" ]]; do
    if [[ -f "$dir/terragrunt.hcl" ]]; then
      if [[ -z "${SEEN[$dir]:-}" ]]; then
        SEEN["$dir"]=1
        RESULT+=("$dir")
      fi
      break
    fi
    dir=$(dirname "$dir")
  done
done <<< "${CHANGED_FILES}"

# Emit space-separated paths on a single line.
printf '%s\n' "${RESULT[*]:-}"
