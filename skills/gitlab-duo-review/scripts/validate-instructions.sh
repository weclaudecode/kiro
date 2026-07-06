#!/usr/bin/env bash
# validate-instructions.sh — validate a GitLab Duo mr-review-instructions.yaml
#
# Checks:
#   - file exists and is valid YAML (via python3, if available)
#   - top-level `instructions:` is a non-empty list
#   - every group has a non-empty `name` and non-empty `instructions`
#   - `fileFilters`, when present, is a list of strings
#   - glob sanity: warns on likely mistakes (e.g. `*.py` intended to be `**/*.py`)
#   - phrasing lint: warns on mandate words ("always", "never", "must")
#     that the reviewer cannot guarantee (see references/best-practices.md)
#
# Usage:
#   scripts/validate-instructions.sh [path]
#     path defaults to .gitlab/duo/mr-review-instructions.yaml
#
# Exit codes: 0 = valid (warnings allowed), 1 = errors found, 2 = usage/env.

set -euo pipefail

path="${1:-.gitlab/duo/mr-review-instructions.yaml}"
[[ -f "$path" ]] || { echo "ERROR: file not found: $path" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 required for validation (PyYAML)." >&2; exit 2; }

python3 - "$path" <<'PY'
import sys

path = sys.argv[1]
try:
    import yaml
except Exception:
    print("ERROR: PyYAML not installed. Try: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

errors, warnings = [], []

with open(path) as fh:
    raw = fh.read()
try:
    doc = yaml.safe_load(raw)
except yaml.YAMLError as e:
    print(f"ERROR: invalid YAML: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(doc, dict) or "instructions" not in doc:
    errors.append("top-level `instructions:` key is missing")
    groups = []
else:
    groups = doc["instructions"]
    if not isinstance(groups, list) or not groups:
        errors.append("`instructions` must be a non-empty list of groups")
        groups = []

MANDATES = ("always", "never", "must ", "must,", "must.", "mandatory", "required to")
seen_names = set()

for i, g in enumerate(groups):
    where = f"group #{i+1}"
    if not isinstance(g, dict):
        errors.append(f"{where}: not a mapping")
        continue
    name = g.get("name")
    if not name or not str(name).strip():
        errors.append(f"{where}: missing/empty `name`")
    else:
        where = f"group '{name}'"
        if name in seen_names:
            warnings.append(f"{where}: duplicate group name")
        seen_names.add(name)

    instr = g.get("instructions")
    if not instr or not str(instr).strip():
        errors.append(f"{where}: missing/empty `instructions`")
    else:
        low = str(instr).lower()
        hits = sorted({m.strip().rstrip(',.') for m in MANDATES if m in low})
        if hits:
            warnings.append(
                f"{where}: mandate phrasing {hits} — Duo cannot guarantee "
                "mandates; prefer 'prefer/flag/check that' (see best-practices.md)")

    ff = g.get("fileFilters", None)
    if ff is not None:
        if not isinstance(ff, list) or not ff:
            errors.append(f"{where}: `fileFilters` must be a non-empty list when present")
        else:
            has_positive = False
            for pat in ff:
                if not isinstance(pat, str):
                    errors.append(f"{where}: fileFilter is not a string: {pat!r}")
                    continue
                if not pat.startswith("!"):
                    has_positive = True
                # glob sanity: a lone *.ext only matches repo root
                if pat.startswith("*.") and "/" not in pat:
                    warnings.append(
                        f"{where}: '{pat}' matches the repo ROOT only; "
                        f"use '**/{pat}' to match nested files")
            if not has_positive:
                # only-negations is valid (means everything-except); note it
                warnings.append(
                    f"{where}: only negated fileFilters — this selects ALL files "
                    "except the excluded set (intended?)")

for w in warnings:
    print(f"WARN:  {w}")
for e in errors:
    print(f"ERROR: {e}")

n_groups = len(groups)
if errors:
    print(f"\nInvalid: {len(errors)} error(s), {len(warnings)} warning(s) across {n_groups} group(s).")
    sys.exit(1)
print(f"\nValid: {n_groups} group(s), {len(warnings)} warning(s).")
sys.exit(0)
PY
