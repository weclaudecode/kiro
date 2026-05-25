#!/usr/bin/env bash
# Weekly steering refresh. Summarizes recent commits and asks the
# steering-curator agent to propose edits to .kiro/steering/ so project context
# doesn't drift. Proposes unified diffs only — never applies. Read-only.
#
# Requires: kiro-cli, KIRO_API_KEY.
# Config (env): REPO_DIR, SINCE, OUT.
#
# crontab:  0 3 * * 1  REPO_DIR=/repos/my-project /path/to/kiro-steering-refresh.sh
set -euo pipefail

REPO_DIR="${REPO_DIR:-$PWD}"
SINCE="${SINCE:-7 days ago}"
OUT="${OUT:-${TMPDIR:-/tmp}/steering-refresh-$(date +%F).diff}"

command -v kiro-cli >/dev/null 2>&1 || { echo "kiro-cli not found on PATH" >&2; exit 1; }
[ -n "${KIRO_API_KEY:-}" ] || { echo "KIRO_API_KEY not set" >&2; exit 1; }

cd "$REPO_DIR"

git log --since="$SINCE" --stat | kiro-cli chat --no-interactive \
  --agent steering-curator \
  --trust-tools read,grep \
  "Here is the recent commit history. Identify conventions or stack facts that drifted from .kiro/steering/ and propose edits as unified diffs. Do not apply them." \
  > "$OUT" 2>&1 || true

echo "steering refresh proposals written to $OUT (review with: git apply --check $OUT)"
