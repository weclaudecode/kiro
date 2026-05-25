#!/usr/bin/env bash
# Nightly GitLab pipeline triage. Pulls the last 24h of failed pipelines via
# glab, traces each, and asks the pipeline-troubleshooter agent for a root cause.
# Produces a digest you can mail or post. Read-only (--trust-tools read,grep).
#
# Requires: glab, jq, kiro-cli, KIRO_API_KEY.
# Config (env): REPO_DIR, REPORT, LOOKBACK_SECONDS, TRIAGE_EMAIL.
#
# crontab:  0 2 * * *  REPO_DIR=/repos/my-project /path/to/kiro-pipeline-triage.sh
set -euo pipefail

REPO_DIR="${REPO_DIR:-$PWD}"
REPORT="${REPORT:-${TMPDIR:-/tmp}/triage-report-$(date +%F).md}"
LOOKBACK_SECONDS="${LOOKBACK_SECONDS:-86400}"

for bin in glab jq kiro-cli; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin not found on PATH" >&2; exit 1; }
done
[ -n "${KIRO_API_KEY:-}" ] || { echo "KIRO_API_KEY not set" >&2; exit 1; }

cd "$REPO_DIR"
: > "$REPORT"

FAILED="$(glab ci list --status=failed --per-page=20 --output=json \
  | jq -r --argjson age "$LOOKBACK_SECONDS" \
      '.[] | select((.created_at | fromdateiso8601) > (now - $age)) | .id')"

[ -z "$FAILED" ] && { echo "no failed pipelines in the last ${LOOKBACK_SECONDS}s"; exit 0; }

for PID in $FAILED; do
  LOG="${TMPDIR:-/tmp}/pipeline-$PID.log"
  glab ci trace "$PID" > "$LOG" 2>&1 || true
  {
    echo "## pipeline $PID"
    kiro-cli chat --no-interactive \
      --agent pipeline-troubleshooter \
      --trust-tools read,grep \
      --resources "file://$LOG" \
      "Identify the root cause of this failed pipeline. Output JSON: {category, root_cause, fix_steps, related_files}." \
      || true
    echo
  } >> "$REPORT"
done

if [ -s "$REPORT" ] && command -v mail >/dev/null 2>&1 && [ -n "${TRIAGE_EMAIL:-}" ]; then
  mail -s "Pipeline triage $(date +%F)" "$TRIAGE_EMAIL" < "$REPORT"
fi
echo "triage written to $REPORT"
