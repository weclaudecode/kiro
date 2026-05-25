#!/usr/bin/env bash
# Shared helpers for the kiro headless git hooks. Sourced by every hook.
#
# Two guards every hook honors:
#   KIRO_SKIP=1 git commit ...   bypasses the hook without --no-verify
#   fail-open                    a missing binary or key never blocks git
#
# All kiro invocations run read-only (--trust-tools read,grep) so a hook can
# never write code without your eyes on it.

# True when the universal skip switch is set: KIRO_SKIP=1 git <cmd> ...
kiro_skip() { [ -n "${KIRO_SKIP:-}" ]; }

# Fail open when tooling is unavailable, so a missing binary or unset key
# never blocks a local git operation. Returns non-zero (=> hook should exit 0).
kiro_ready() {
  if ! command -v kiro-cli >/dev/null 2>&1; then
    echo "[kiro-hook] kiro-cli not on PATH — skipping" >&2
    return 1
  fi
  if [ -z "${KIRO_API_KEY:-}" ]; then
    echo "[kiro-hook] KIRO_API_KEY not set — skipping" >&2
    return 1
  fi
  return 0
}

# Default tool trust: read + grep only. Never write, never shell.
KIRO_TRUST="${KIRO_TRUST:-read,grep}"

# Where transient hook artifacts (reports, patches, logs) land.
KIRO_TMP="${TMPDIR:-/tmp}"
