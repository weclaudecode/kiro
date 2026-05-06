#!/usr/bin/env bash
#
# detect-changed-units.sh
#
# Emits a space-separated list of `--terragrunt-include-dir <path>` flags
# for every Terragrunt unit affected by the current branch's changes,
# relative to the merge base with the target branch.
#
# A unit is considered changed when:
#   - its own terragrunt.hcl changed, or
#   - any file inside its directory changed, or
#   - a file it transitively includes changed (root terragrunt.hcl, env.hcl,
#     account.hcl, region.hcl, or anything under _envcommon/).
#
# Intended for use inside a CI plan job that has already cd'd into the
# Terragrunt live root:
#
#   INCLUDE_ARGS=$(./scripts/detect-changed-units.sh)
#   terragrunt run-all plan --terragrunt-non-interactive ${INCLUDE_ARGS}
#
# Environment:
#   BASE_REF   target branch to diff against (default: origin/main)
#   LIVE_ROOT  path to the live root from the repo root (default: live)

set -euo pipefail

BASE_REF="${BASE_REF:-origin/main}"
LIVE_ROOT="${LIVE_ROOT:-live}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository" >&2
  exit 1
fi

# Compute the merge base. In a detached CI checkout the base ref may need
# to be fetched first; the caller is expected to handle that.
if ! MERGE_BASE=$(git merge-base HEAD "${BASE_REF}" 2>/dev/null); then
  echo "ERROR: cannot find merge base with ${BASE_REF}" >&2
  exit 1
fi

CHANGED_FILES=$(git diff --name-only "${MERGE_BASE}" HEAD)

if [[ -z "${CHANGED_FILES}" ]]; then
  # Nothing changed; emit nothing so the caller can short-circuit.
  exit 0
fi

# Detect "everything" triggers — files whose change invalidates the entire
# fleet. If any of these change, emit no include flags so run-all covers
# all units.
FLEET_WIDE_PATTERNS=(
  "^${LIVE_ROOT}/terragrunt\.hcl$"
  "^${LIVE_ROOT}/env\.hcl$"
)
for pattern in "${FLEET_WIDE_PATTERNS[@]}"; do
  if echo "${CHANGED_FILES}" | grep -Eq "${pattern}"; then
    # Caller treats empty output as "run everything".
    exit 0
  fi
done

declare -A UNITS=()

add_unit() {
  local dir="$1"
  # Walk up until we find a directory containing terragrunt.hcl that is not
  # the root.
  while [[ "${dir}" != "." && "${dir}" != "/" ]]; do
    if [[ -f "${dir}/terragrunt.hcl" && "${dir}" != "${LIVE_ROOT}" ]]; then
      UNITS["${dir}"]=1
      return
    fi
    dir=$(dirname "${dir}")
  done
}

# Map account.hcl / region.hcl / _envcommon changes to all descendant units.
expand_scoped_change() {
  local file="$1"
  local scope_dir
  case "${file}" in
    *"/account.hcl")
      scope_dir=$(dirname "${file}")
      ;;
    *"/region.hcl")
      scope_dir=$(dirname "${file}")
      ;;
    "${LIVE_ROOT}/_envcommon/"*)
      # An _envcommon change affects every unit that includes it. Without
      # parsing HCL we conservatively treat it as fleet-wide.
      exit 0
      ;;
    *)
      return
      ;;
  esac
  while IFS= read -r tg; do
    add_unit "$(dirname "${tg}")"
  done < <(find "${scope_dir}" -name 'terragrunt.hcl' -not -path "${LIVE_ROOT}/terragrunt.hcl")
}

while IFS= read -r file; do
  [[ -z "${file}" ]] && continue
  case "${file}" in
    "${LIVE_ROOT}/"*)
      expand_scoped_change "${file}"
      add_unit "$(dirname "${file}")"
      ;;
    *)
      # File outside the live tree (module source, scripts, CI config).
      # Conservative behaviour: ignore here. CI may set BASE_REF to an empty
      # value or invoke run-all without include flags to cover module bumps.
      ;;
  esac
done <<< "${CHANGED_FILES}"

if [[ ${#UNITS[@]} -eq 0 ]]; then
  exit 0
fi

OUTPUT=()
for unit in "${!UNITS[@]}"; do
  # Strip the leading LIVE_ROOT/ so the path is relative to the cwd the
  # caller will run terragrunt from (which is LIVE_ROOT).
  rel="${unit#${LIVE_ROOT}/}"
  OUTPUT+=("--terragrunt-include-dir" "${rel}")
done

echo "${OUTPUT[@]}"
