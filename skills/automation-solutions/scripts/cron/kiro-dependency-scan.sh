#!/usr/bin/env bash
# Nightly dependency / CVE scan. Runs pip-audit (Python) and trivy (filesystem),
# then asks kiro to triage the raw findings into an actionable digest. Read-only.
#
# Requires: kiro-cli, KIRO_API_KEY. Optional: pip-audit, trivy (at least one).
# Config (env): REPO_DIR, REPORT.
#
# crontab:  30 2 * * *  REPO_DIR=/repos/my-project /path/to/kiro-dependency-scan.sh
set -euo pipefail

REPO_DIR="${REPO_DIR:-$PWD}"
REPORT="${REPORT:-${TMPDIR:-/tmp}/dep-scan-$(date +%F).md}"
RAW="${TMPDIR:-/tmp}/dep-scan-raw-$(date +%F).txt"

command -v kiro-cli >/dev/null 2>&1 || { echo "kiro-cli not found on PATH" >&2; exit 1; }
[ -n "${KIRO_API_KEY:-}" ] || { echo "KIRO_API_KEY not set" >&2; exit 1; }

cd "$REPO_DIR"
: > "$RAW"

if command -v pip-audit >/dev/null 2>&1; then
  echo "## pip-audit" >> "$RAW"
  pip-audit --progress-spinner off >> "$RAW" 2>&1 || true
fi
if command -v trivy >/dev/null 2>&1; then
  echo "## trivy fs" >> "$RAW"
  trivy fs --scanners vuln --quiet . >> "$RAW" 2>&1 || true
fi

[ -s "$RAW" ] || { echo "no scanner output — install pip-audit and/or trivy"; exit 0; }

kiro-cli chat --no-interactive \
  --trust-tools read,grep \
  --resources "file://$RAW" \
  "Triage these dependency-scan results. Group by severity, drop duplicates and noise, and for each real issue give: package, current vs fixed version, exploitability in this repo's context, and the one-line upgrade command. Output Markdown." \
  > "$REPORT" 2>&1 || true

echo "dependency scan written to $REPORT"
