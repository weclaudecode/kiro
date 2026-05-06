#!/usr/bin/env bash
# Prints the catalog inventory and the destination each artifact would
# install to, given a chosen scope.
#
# Usage:
#   scripts/list.sh                              # show with scope=global
#   scripts/list.sh --scope project ~/code/repo  # show with project scope

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.txt"

scope="global"
project_path=""

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
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$scope" in
  global) kiro_root="$HOME/.kiro" ;;
  project)
    [[ -d "$project_path" ]] || { echo "not a directory: $project_path" >&2; exit 2; }
    kiro_root="$(cd "$project_path" && pwd)/.kiro" ;;
  *) echo "scope must be 'global' or 'project'" >&2; exit 2 ;;
esac

printf '%-5s  %-50s  %s\n' "TYPE" "SOURCE" "DEST (scope=$scope)"
printf '%-5s  %-50s  %s\n' "----" "------" "----"

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  IFS='|' read -r kind src dest <<<"$line"
  exists=""
  [[ -e "$kiro_root/$dest" ]] && exists=" (installed)"
  printf '%-5s  %-50s  %s%s\n' "$kind" "$src" "$kiro_root/$dest" "$exists"
done < "$MANIFEST"
