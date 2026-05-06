#!/usr/bin/env bash
# Interactive per-artifact installer for the kiro config catalog.
# Asks Y/N for each artifact. Defaults to N. Never bulk-installs.
#
# Usage:
#   scripts/install.sh                                  # interactive, scope=global
#   scripts/install.sh --scope global                   # ~/.kiro/<dest>
#   scripts/install.sh --scope project ~/code/my-repo   # <project>/.kiro/<dest>
#   scripts/install.sh --dry-run                        # show actions, write nothing
#   scripts/install.sh --yes-to <pattern>               # auto-yes for matching dest paths
#
# Scope and --yes-to can combine: --scope project ~/code/foo --yes-to 'steering/*'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.txt"

scope="global"
project_path=""
dry_run=false
yes_pattern=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      scope="${2:?--scope needs an argument}"
      if [[ "$scope" == "project" ]]; then
        project_path="${3:?--scope project needs a path}"
        shift 3
      else
        shift 2
      fi
      ;;
    --dry-run) dry_run=true; shift ;;
    --yes-to) yes_pattern="${2:?--yes-to needs a pattern}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$scope" in
  global)
    kiro_root="$HOME/.kiro"
    ;;
  project)
    [[ -d "$project_path" ]] || { echo "project path not a directory: $project_path" >&2; exit 2; }
    kiro_root="$(cd "$project_path" && pwd)/.kiro"
    ;;
  *) echo "scope must be 'global' or 'project'" >&2; exit 2 ;;
esac

printf '\nkiro catalog installer\n  source:  %s\n  dest:    %s\n  dry-run: %s\n\n' \
  "$REPO_ROOT" "$kiro_root" "$dry_run"

installed=0
skipped=0
overwritten=0

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  IFS='|' read -r kind src dest <<<"$line"
  src_abs="$REPO_ROOT/$src"
  dest_abs="$kiro_root/$dest"

  if [[ ! -e "$src_abs" ]]; then
    printf '  [missing] %s — skipping (catalog source not found)\n' "$src" >&2
    skipped=$((skipped + 1))
    continue
  fi

  # Auto-yes pattern match against dest path
  reply=""
  if [[ -n "$yes_pattern" ]] && [[ "$dest" == $yes_pattern ]]; then
    reply="y"
    printf 'Install %s → %s? [auto-yes]\n' "$src" "$dest_abs"
  else
    if [[ -e "$dest_abs" ]]; then
      printf 'Install %s → %s [EXISTS, will overwrite]? [y/N] ' "$src" "$dest_abs"
    else
      printf 'Install %s → %s? [y/N] ' "$src" "$dest_abs"
    fi
    read -r reply || reply=""
  fi

  case "$reply" in
    y|Y|yes|YES)
      if [[ "$dry_run" == "true" ]]; then
        printf '  [dry-run] would write %s\n' "$dest_abs"
      else
        mkdir -p "$(dirname "$dest_abs")"
        if [[ "$kind" == "dir" ]]; then
          [[ -e "$dest_abs" ]] && overwritten=$((overwritten + 1))
          rm -rf "$dest_abs"
          cp -R "$src_abs" "$dest_abs"
        else
          [[ -e "$dest_abs" ]] && overwritten=$((overwritten + 1))
          cp "$src_abs" "$dest_abs"
        fi
        printf '  installed.\n'
      fi
      installed=$((installed + 1))
      ;;
    *)
      skipped=$((skipped + 1))
      ;;
  esac
done < "$MANIFEST"

printf '\nDone. installed=%d  overwritten=%d  skipped=%d  dry_run=%s\n' \
  "$installed" "$overwritten" "$skipped" "$dry_run"
