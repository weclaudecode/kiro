#!/usr/bin/env bash
# kiro-headless.sh — a hardened wrapper for running kiro-cli non-interactively
# in CI, cron, or git hooks. REFERENCE / COPY-PASTE (not installed by the
# catalog installer). Adapt to your environment.
#
# What it adds over a raw `kiro-cli chat --no-interactive`:
#   - fails fast and loudly if KIRO_API_KEY / auth is missing
#   - forces a READ-ONLY trust scope by default (override with --trust)
#   - reads context from stdin if present (e.g. a piped diff or log)
#   - never enables --trust-all-tools
#
# Usage:
#   kiro-headless.sh [--agent NAME] [--trust LIST] "PROMPT"
#   git diff | kiro-headless.sh --agent mr-reviewer "Review this diff"
#
# Env:
#   KIRO_API_KEY   required in non-interactive contexts (ksk_...)
#   KIRO_TRUST     default trust list (default: read,grep)

set -euo pipefail

agent=""
trust="${KIRO_TRUST:-read,grep}"
prompt=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) agent="${2:?--agent needs a name}"; shift 2 ;;
    --trust) trust="${2:?--trust needs a list}"; shift 2 ;;
    --trust-all*|--trust-all-tools)
      echo "kiro-headless: refusing --trust-all-tools; pass an explicit --trust list" >&2
      exit 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) prompt="$1"; shift ;;
  esac
done

[[ -n "$prompt" ]] || { echo "kiro-headless: a prompt argument is required" >&2; exit 2; }
command -v kiro-cli >/dev/null 2>&1 || { echo "kiro-headless: kiro-cli not on PATH" >&2; exit 127; }

# Verify auth without leaking the key. whoami --format json IS structured.
if ! kiro-cli whoami --format json >/dev/null 2>&1; then
  echo "kiro-headless: not authenticated. Set KIRO_API_KEY (ksk_...) as a masked CI variable." >&2
  exit 3
fi

args=(chat --no-interactive --trust-tools="$trust" --require-mcp-startup)
[[ -n "$agent" ]] && args+=(--agent "$agent")

# If stdin is piped (not a TTY), feed it as context.
if [[ ! -t 0 ]]; then
  kiro-cli "${args[@]}" "$prompt" < /dev/stdin
else
  kiro-cli "${args[@]}" "$prompt"
fi
