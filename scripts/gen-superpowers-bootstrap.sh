#!/usr/bin/env bash
# Generate the Superpowers session-start bootstrap steering file.
#
# Kiro has no session-start hook that can inject context (agentSpawn stdout is
# not added to the conversation), so the bootstrap rides Kiro's always-on
# steering instead: kiro-cli loads every file in .kiro/steering/ regardless of
# inclusion mode. This script inlines the two things the bootstrap must carry —
# the using-superpowers skill and the Kiro tool mapping — into one steering file
# so they cannot drift from their sources.
#
# Usage:
#   scripts/gen-superpowers-bootstrap.sh            # write steering/superpowers-bootstrap.md
#   scripts/gen-superpowers-bootstrap.sh --check    # fail if the committed file is stale

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL="$REPO_ROOT/skills/using-superpowers/SKILL.md"
MAPPING="$REPO_ROOT/skills/using-superpowers/references/kiro-tools.md"
OUT="$REPO_ROOT/steering/superpowers-bootstrap.md"

for f in "$SKILL" "$MAPPING"; do
  [[ -f "$f" ]] || { echo "missing source: $f" >&2; exit 1; }
done

# Drop the leading YAML frontmatter block from SKILL.md — steering files carry
# their own frontmatter, and two blocks would break parsing.
strip_frontmatter() {
  awk 'NR==1 && $0=="---" {infm=1; next} infm && $0=="---" {infm=0; next} !infm {print}' "$1"
}

render() {
  cat <<'HEADER'
---
inclusion: always
---

<!--
  GENERATED FILE — do not edit by hand.
  Source: skills/using-superpowers/SKILL.md
          skills/using-superpowers/references/kiro-tools.md
  Regenerate: scripts/gen-superpowers-bootstrap.sh
-->

<EXTREMELY_IMPORTANT>
You have superpowers.

**Below is the full content of your `superpowers:using-superpowers` skill — your
introduction to using skills. It is already loaded; do not try to load it again.
Every other skill lives in `.kiro/skills/<name>/SKILL.md` and is activated the
Kiro way: automatic description match, `/skill-name`, or reading its `SKILL.md`
(see the Kiro tool mapping at the end of this file).**

HEADER

  strip_frontmatter "$SKILL"

  cat <<'SEPARATOR'

---

**Kiro tool mapping — how the actions the skills ask for map to Kiro's real
tools. This is the platform adaptation referenced by "Platform Adaptation" above.**

SEPARATOR

  strip_frontmatter "$MAPPING"

  cat <<'FOOTER'

</EXTREMELY_IMPORTANT>
FOOTER
}

if [[ "${1:-}" == "--check" ]]; then
  if diff -q <(render) "$OUT" >/dev/null 2>&1; then
    echo "steering/superpowers-bootstrap.md is up to date"
    exit 0
  fi
  echo "steering/superpowers-bootstrap.md is STALE — run scripts/gen-superpowers-bootstrap.sh" >&2
  diff -u "$OUT" <(render) || true
  exit 1
fi

render > "$OUT"
echo "wrote $OUT"
