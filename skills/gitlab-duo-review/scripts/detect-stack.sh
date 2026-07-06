#!/usr/bin/env bash
# detect-stack.sh — read-only inventory of a repo to seed GitLab Duo
# custom review instruction groups.
#
# Prints: top source extensions by file count, framework/manifest markers,
# test/IaC/CI/container presence, existing convention files, and suggested
# fileFilters globs for an mr-review-instructions.yaml.
#
# Usage:
#   scripts/detect-stack.sh [repo_path]   # defaults to current directory
#
# Read-only: never writes or mutates anything.

set -euo pipefail

repo="${1:-.}"
[[ -d "$repo" ]] || { echo "not a directory: $repo" >&2; exit 2; }
repo="$(cd "$repo" && pwd)"

# Prefer git's tracked-file list (respects .gitignore); fall back to find.
list_files() {
  if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$repo" ls-files
  else
    ( cd "$repo" && find . -type f \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/.terraform/*' \
        -not -path '*/.terragrunt-cache/*' \
        -not -path '*/dist/*' -not -path '*/build/*' \
        | sed 's|^\./||' )
  fi
}

mapfile -t FILES < <(list_files)
total=${#FILES[@]}
[[ $total -gt 0 ]] || { echo "no files found under $repo" >&2; exit 1; }

has() { # has <glob-substring>: true if any tracked path matches (case-insensitive)
  printf '%s\n' "${FILES[@]}" | grep -qiE "$1"
}
count() { printf '%s\n' "${FILES[@]}" | grep -icE "$1" || true; }

echo "# Stack inventory for: $repo"
echo "# tracked files: $total"
echo

echo "## Top source extensions (by count)"
printf '%s\n' "${FILES[@]}" \
  | grep -oE '\.[A-Za-z0-9_]+$' \
  | grep -viE '\.(lock|sum|log|min\.[a-z]+)$' \
  | sort | uniq -c | sort -rn | head -20 \
  | awk '{printf "  %6d  %s\n", $1, $2}'
echo

echo "## Detected markers"
declare -a groups=()   # collect suggested group|glob lines

mark() { printf '  [x] %s\n' "$1"; }

# --- Languages / frameworks -------------------------------------------------
if has '\.py$'; then
  mark "Python ($(count '\.py$') files)"
  if has 'requirements.*\.txt$|pyproject\.toml$|Pipfile$|poetry\.lock$'; then
    mark "  Python packaging manifest present"
  fi
  if has 'aws_lambda_powertools|template\.yaml$|serverless\.yml$|samconfig'; then
    mark "  AWS Lambda / serverless markers"
  fi
  groups+=("Python|\"**/*.py\", \"!**/*_test.py\", \"!**/test_*.py\", \"!tests/**/*\"")
  groups+=("Python Tests|\"**/*_test.py\", \"**/test_*.py\", \"tests/**/*.py\"")
fi
if has '\.(ts|tsx)$'; then
  mark "TypeScript ($(count '\.(ts|tsx)$') files)"
  has 'package\.json$' && mark "  package.json present"
  groups+=("TypeScript Source|\"**/*.ts\", \"**/*.tsx\", \"!**/*.test.ts\", \"!**/*.spec.ts\"")
  groups+=("Frontend Tests|\"**/*.test.ts\", \"**/*.test.tsx\", \"**/*.spec.ts\"")
fi
if has '\.(js|jsx)$'; then
  mark "JavaScript ($(count '\.(js|jsx)$') files)"
fi
has '\.go$'   && { mark "Go ($(count '\.go$') files)";   groups+=("Go|\"**/*.go\", \"!**/*_test.go\""); groups+=("Go Tests|\"**/*_test.go\""); }
has '\.rb$'   && { mark "Ruby ($(count '\.rb$') files)";  groups+=("Ruby|\"**/*.rb\", \"!spec/**/*.rb\""); groups+=("Ruby Specs|\"spec/**/*_spec.rb\""); }
has '\.java$' && { mark "Java ($(count '\.java$') files)"; groups+=("Java|\"**/*.java\", \"!**/*Test.java\""); }
has '\.rs$'   && { mark "Rust ($(count '\.rs$') files)";  groups+=("Rust|\"**/*.rs\""); }

# --- Infrastructure as code -------------------------------------------------
if has '\.tf$'; then
  mark "Terraform ($(count '\.tf$') files)"
  groups+=("Terraform|\"**/*.tf\", \"!**/.terraform/**\"")
fi
if has 'terragrunt\.hcl$'; then
  mark "Terragrunt"
  groups+=("Terragrunt|\"**/terragrunt.hcl\", \"!**/.terragrunt-cache/**\"")
fi
if has '(^|/)(k8s|manifests|kustomize|charts)/|\.k8s\.ya?ml$|Chart\.yaml$'; then
  mark "Kubernetes / Helm / Kustomize markers"
  groups+=("Kubernetes Manifests|\"k8s/**/*.yaml\", \"manifests/**/*.yaml\", \"charts/**/*.yaml\"")
fi

# --- CI / containers --------------------------------------------------------
if has '\.gitlab-ci\.yml$|(^|/)\.gitlab/ci/'; then
  mark "GitLab CI pipeline"
  groups+=("GitLab CI Pipelines|\".gitlab-ci.yml\", \".gitlab/ci/**/*.yml\"")
fi
has '(^|/)\.github/workflows/' && mark "GitHub Actions workflows"
has '(^|/)Dockerfile|\.dockerfile$' && { mark "Dockerfile(s)"; groups+=("Dockerfiles|\"**/Dockerfile\", \"**/*.dockerfile\""); }

# --- Existing conventions to read ------------------------------------------
echo
echo "## Convention files to read before authoring"
found_conv=0
for f in CONTRIBUTING.md .editorconfig .rubocop.yml .eslintrc .eslintrc.js \
         .eslintrc.json ruff.toml pyproject.toml .golangci.yml \
         .prettierrc STYLE.md CODE_STYLE.md; do
  if [[ -e "$repo/$f" ]]; then printf '  - %s\n' "$f"; found_conv=1; fi
done
if [[ -d "$repo/.kiro/steering" ]]; then
  printf '  - .kiro/steering/ (%s files)\n' "$(find "$repo/.kiro/steering" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  found_conv=1
fi
[[ $found_conv -eq 0 ]] && echo "  (none found — infer conventions from the code itself)"

# --- Existing Duo instructions ---------------------------------------------
echo
if [[ -e "$repo/.gitlab/duo/mr-review-instructions.yaml" ]]; then
  echo "## Existing .gitlab/duo/mr-review-instructions.yaml FOUND — tune it, don't overwrite blindly."
else
  echo "## No .gitlab/duo/mr-review-instructions.yaml yet — this repo is unconfigured."
fi

# --- Suggested groups -------------------------------------------------------
echo
echo "## Suggested instruction groups (seed for mr-review-instructions.yaml)"
echo "#  Always add an unfiltered 'All Files' group for universal points."
if [[ ${#groups[@]} -eq 0 ]]; then
  echo "  (no language markers matched — inspect the extension table above manually)"
else
  for g in "${groups[@]}"; do
    name="${g%%|*}"; globs="${g#*|}"
    printf '  - name: %s\n    fileFilters: [ %s ]\n' "$name" "$globs"
  done
fi
echo
echo "# Next: harvest concrete review points per group (see references/best-practices.md),"
echo "#       phrase as numbered hints, then run scripts/validate-instructions.sh."
