#!/usr/bin/env bash
# grep-patterns.sh — quick-scan grep one-liners for common security antipatterns.
#
# Usage:
#   ./scripts/grep-patterns.sh                # run all scans, print counts
#   ./scripts/grep-patterns.sh scan_pickle    # run a single scan
#
# Requires: ripgrep (rg). Falls back to grep -rE if rg is not installed.
#
# This script is a starting point for the boundary walk, not a substitute
# for it. It catches well-known antipatterns; business-logic flaws (IDOR,
# multi-tenant bleed, missing authz) need human review.

set -euo pipefail

if command -v rg >/dev/null 2>&1; then
  RG="rg --no-heading --line-number --color=never"
else
  RG="grep -rEn --color=never"
fi

ROOT="${1:-.}"

scan_secrets() {
  echo "== scan_secrets (hardcoded passwords / api keys / tokens) =="
  $RG -i '(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*["\x27][^"\x27[:space:]$]{6,}["\x27]' "$ROOT" || true
}

scan_aws_keys() {
  echo "== scan_aws_keys (AWS access key IDs) =="
  $RG 'AKIA[0-9A-Z]{16}' "$ROOT" || true
  echo "-- AWS secret key heuristic (40-char base64-ish following 'aws' context):"
  $RG -i 'aws.{0,30}["\x27][A-Za-z0-9/+=]{40}["\x27]' "$ROOT" || true
}

scan_pickle() {
  echo "== scan_pickle (Python pickle/marshal/cPickle) =="
  $RG '\b(pickle|cPickle|marshal)\.loads?\s*\(' "$ROOT" || true
}

scan_yaml_load() {
  echo "== scan_yaml_load (Python yaml.load — should be safe_load) =="
  $RG 'yaml\.load\s*\(' "$ROOT" || true
}

scan_eval() {
  echo "== scan_eval (eval / exec / Function-string) =="
  $RG '\b(eval|exec)\s*\(' "$ROOT" || true
  $RG '\bnew\s+Function\s*\(' "$ROOT" || true
}

scan_subprocess_shell() {
  echo "== scan_subprocess_shell (subprocess shell=True / os.system / child_process.exec) =="
  $RG 'subprocess\.\w+\s*\([^)]*shell\s*=\s*True' "$ROOT" || true
  $RG '\bos\.system\s*\(' "$ROOT" || true
  $RG 'child_process\.exec\s*\(' "$ROOT" || true
  $RG 'Runtime\.getRuntime\s*\(\s*\)\s*\.exec\s*\(' "$ROOT" || true
}

scan_md5_sha1() {
  echo "== scan_md5_sha1 (weak hashes used for password / token) =="
  $RG -i '\b(md5|sha1)\s*\(' "$ROOT" || true
  $RG -i 'hashlib\.(md5|sha1)\s*\(' "$ROOT" || true
  $RG -i 'MessageDigest\.getInstance\(\s*"(MD5|SHA-?1)"' "$ROOT" || true
}

scan_jwt_none() {
  echo "== scan_jwt_none (alg: none accepted / signature verification disabled) =="
  $RG -i 'verify_signature\s*[:=]\s*false' "$ROOT" || true
  $RG -i 'algorithms?\s*[:=]\s*\[?\s*["\x27]?none["\x27]?\s*\]?' "$ROOT" || true
  $RG 'jwt\.decode\s*\([^)]*verify\s*=\s*False' "$ROOT" || true
}

scan_sql_format() {
  echo "== scan_sql_format (SQL built by string formatting / template literals) =="
  $RG '(execute|query)\s*\(\s*[fF]?["\x27].*\{' "$ROOT" || true
  $RG '(execute|query)\s*\(\s*`[^`]*\$\{' "$ROOT" || true
}

scan_innerhtml() {
  echo "== scan_innerhtml (innerHTML / dangerouslySetInnerHTML / document.write) =="
  $RG '\.innerHTML\s*=' "$ROOT" || true
  $RG 'dangerouslySetInnerHTML' "$ROOT" || true
  $RG 'document\.write\s*\(' "$ROOT" || true
}

scan_math_random() {
  echo "== scan_math_random (Math.random for security-sensitive tokens) =="
  $RG 'Math\.random\s*\(\s*\)' "$ROOT" || true
  $RG '\brandom\.random\s*\(\s*\)' "$ROOT" || true
}

scan_open_sg() {
  echo "== scan_open_sg (CIDR 0.0.0.0/0 in IaC) =="
  $RG '0\.0\.0\.0/0' "$ROOT" || true
}

scan_iam_wildcards() {
  echo "== scan_iam_wildcards (Action: * / Resource: *) =="
  $RG '"Action"\s*:\s*"\*"' "$ROOT" || true
  $RG 'action\s*=\s*"\*"' "$ROOT" || true
  $RG '"Resource"\s*:\s*"\*"' "$ROOT" || true
}

scan_pull_request_target() {
  echo "== scan_pull_request_target (GitHub Actions footgun) =="
  $RG 'pull_request_target' "$ROOT" || true
}

scan_action_tag_pin() {
  echo "== scan_action_tag_pin (GitHub action pinned by tag, not SHA) =="
  $RG 'uses:\s*\S+@v[0-9]' "$ROOT" || true
}

scan_dockerfile_root() {
  echo "== scan_dockerfile_root (Dockerfile USER root or no USER) =="
  $RG '^USER\s+root' "$ROOT" || true
  echo "-- Dockerfiles with no USER directive:"
  while IFS= read -r f; do
    if ! grep -qE '^USER\s' "$f"; then
      echo "$f: no USER directive"
    fi
  done < <(find "$ROOT" -type f \( -name 'Dockerfile' -o -name 'Dockerfile.*' \) 2>/dev/null)
}

main() {
  local scans=(
    scan_secrets
    scan_aws_keys
    scan_pickle
    scan_yaml_load
    scan_eval
    scan_subprocess_shell
    scan_md5_sha1
    scan_jwt_none
    scan_sql_format
    scan_innerhtml
    scan_math_random
    scan_open_sg
    scan_iam_wildcards
    scan_pull_request_target
    scan_action_tag_pin
    scan_dockerfile_root
  )
  local total=0
  for s in "${scans[@]}"; do
    local out
    out="$("$s" 2>/dev/null || true)"
    local count
    count="$(echo "$out" | grep -cE '^[^=-]' || true)"
    printf '%-30s %5s match-lines\n' "$s" "$count"
    total=$((total + count))
  done
  echo "------------------------------"
  printf '%-30s %5s match-lines\n' "TOTAL" "$total"
  echo
  echo "Re-run a single scan to see detail, e.g. ./scripts/grep-patterns.sh scan_pickle"
}

if [[ $# -gt 0 ]] && declare -f "$1" >/dev/null; then
  "$1"
else
  main
fi
