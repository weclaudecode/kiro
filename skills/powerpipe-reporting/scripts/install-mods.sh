#!/usr/bin/env bash
# Install/refresh the Powerpipe dependency mods declared in mod.pp.
# Idempotent: safe to run repeatedly. Versions are pinned in mod.pp — this
# script does NOT bump them (bump intentionally, then review the diff).
#
# Usage:  scripts/install-mods.sh [mod-dir]   (default: current directory)

set -euo pipefail

MOD_DIR="${1:-.}"

if [ ! -f "${MOD_DIR}/mod.pp" ]; then
  echo "No mod.pp in ${MOD_DIR}. Run 'powerpipe mod init' or copy assets/mod.pp first." >&2
  exit 1
fi

command -v powerpipe >/dev/null 2>&1 || {
  echo "powerpipe not found. Install: https://powerpipe.io/downloads" >&2
  exit 1
}

cd "$MOD_DIR"
echo ">> powerpipe mod install  (in $(pwd))"
powerpipe mod install

echo ">> installed mods:"
powerpipe mod list
