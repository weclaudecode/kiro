---
name: automation-solutions
description: Use when setting up or troubleshooting headless / non-interactive kiro-cli automation — git hooks (pre-commit, prepare-commit-msg, commit-msg, post-commit, pre-push) and scheduled jobs (cron, systemd timers, launchd, EventBridge) that run kiro-cli in --no-interactive mode for code review, commit-message drafting, doc sync, security scanning, pipeline triage, dependency CVE scans, and steering refresh. Reach for this whenever the user mentions automating kiro, git hooks, pre-commit / pre-push review, scheduled or cron jobs, nightly scans, or running kiro without a human at the keyboard.
---

# Automation Solutions

## Overview

This skill is a playbook for running kiro-cli **headlessly** — invoked by git
hooks and schedulers instead of a person at a prompt. It ships runnable scripts,
the read-only agents they call, and the trade-offs for each pattern.

One principle holds across every workflow: **a hook never writes code without
your eyes on it.** Every invocation runs with `--trust-tools read,grep`, every
agent is defined read-only, and anything that would change a file (doc updates,
steering edits) is emitted as a unified diff for a human to apply. Hooks fail
open when kiro isn't available and honor a `KIRO_SKIP=1` bypass, so automation
never gets in the way of normal git.

## When to Use

- Wiring kiro into git hooks — local review, commit-message drafting/validation,
  doc sync, pre-push security scan.
- Standing up scheduled kiro jobs — nightly pipeline triage, dependency/CVE
  scans, weekly steering refresh.
- Choosing where an expensive check should live (pre-commit vs. pre-push vs.
  cron) and how to bound its cost.
- Hardening or debugging existing kiro automation (fail-open behavior, skip
  switches, key handling, license isolation).

Don't use this for interactive, in-chat work, or for hooks that *write* code
(auto-format, codegen) — those need their own narrowly-scoped, non-read-only
setup.

## Prerequisites

- `KIRO_API_KEY` exported (treat it like an AWS key — see `secrets-handling`).
- `kiro-cli` on `PATH`.
- The agents below installed in `~/.kiro/agents/` or the project's
  `.kiro/agents/` (all read-only).

> Headless flag surface varies by kiro-cli version. The scripts use
> `kiro-cli chat --no-interactive ... "<prompt>"`; confirm against
> `kiro-cli chat --help` on your build (some expose `kiro-cli -p`).

## Workflows at a glance

| # | Trigger | What it does | Cost / cadence |
| --- | --- | --- | --- |
| 1 | pre-commit | Review staged diff, block on critical | ~10-30s every commit |
| 2 | prepare-commit-msg | Draft a conventional-commit message | every interactive commit |
| 2b | commit-msg | Validate message is conventional (local regex) | free, every commit |
| 3 | post-commit | Async doc-sync proposals (background) | ~once per commit, off the critical path |
| 4 | pre-push | Heavier review + security scan, block on critical | ~30-90s per push |
| 5 | cron (nightly) | Triage failed GitLab pipelines | bounded by # failures |
| 6 | cron (nightly) | Dependency / CVE scan triage | one run/night |
| 7 | cron (weekly) | Refresh `.kiro/steering/` from recent commits | one run/week |

Full descriptions and trade-offs: `references/workflows.md`.
**Pre-push is the best-ROI hook** — full coverage, fires only on push.

## Installing the git hooks

`.git/hooks/` is never tracked, so hooks placed there don't follow the repo. Use
a tracked `.githooks/` directory via `core.hooksPath`:

```bash
# from this skill's directory
scripts/install-hooks.sh ~/code/my-repo
# copies the hooks into <repo>/.githooks/, sets core.hooksPath=.githooks
# then: review them and commit .githooks/ so the team gets them
```

Bypass any hook for a single command with `KIRO_SKIP=1 git commit ...` — this
beats `--no-verify`, which disables *all* hooks at once.

## Scheduling the cron jobs

The cron scripts take config via env (`REPO_DIR`, `REPORT`, etc.). Wire them up
with crontab, a systemd timer, launchd, or EventBridge + a `t4g.nano` — see
`references/scheduling.md` for a unit-file and crontab example of each, and how
to pick.

## Scripts

| Path | Purpose |
| --- | --- |
| `scripts/githooks/_lib.sh` | Shared helpers: `KIRO_SKIP` guard, fail-open `kiro_ready`, default trust |
| `scripts/githooks/pre-commit` | Workflow 1 |
| `scripts/githooks/prepare-commit-msg` | Workflow 2 |
| `scripts/githooks/commit-msg` | Workflow 2b |
| `scripts/githooks/post-commit` | Workflow 3 |
| `scripts/githooks/pre-push` | Workflow 4 |
| `scripts/cron/kiro-pipeline-triage.sh` | Workflow 5 |
| `scripts/cron/kiro-dependency-scan.sh` | Workflow 6 |
| `scripts/cron/kiro-steering-refresh.sh` | Workflow 7 |
| `scripts/install-hooks.sh` | Wire the hooks into a repo via `core.hooksPath` |

## Agents

These read-only agents live in the catalog's top-level `agents/` and install via
`scripts/install.sh`:

| Agent | Used by | Output |
| --- | --- | --- |
| `mr-reviewer` | pre-commit | JSONL findings (gated on `"severity":"critical"`) |
| `security-auditor` | pre-push | Severity-grouped report + verdict |
| `doc-updater` | post-commit | Unified diffs to docs |
| `pipeline-troubleshooter` | pipeline triage | Root-cause JSON |
| `steering-curator` | steering refresh | Unified diffs to steering |

## References

| Reference | Covers |
| --- | --- |
| `references/workflows.md` | Each workflow in full, with rationale and trade-offs |
| `references/scheduling.md` | crontab / systemd timer / launchd / EventBridge, with examples |
| `references/cost-and-safety.md` | Read-only guarantees, fail-open, skip switch, cost, key scope, license isolation, hook portability |

## Gotchas

- **License:** keep kiro invocations isolated (own shell, own env) from
  OpenClaw/NemoClaw-style harnesses — pairing them violates Kiro's ToS.
- **API key scope:** SSO orgs need admin to enable API keys; personal keys come
  from account settings. In cron, read the key from a `chmod 600` env file, not
  a committed crontab.
- **Cost:** headless mode burns credits per call. Pre-commit on every commit is
  the expensive end; pre-push is the sweet spot; the `commit-msg` validator is
  free.
- **Portability:** prefer `core.hooksPath` → tracked `.githooks/` (or
  lefthook/pre-commit) over `.git/hooks/`, which never follows the repo.
- **Skip switch:** `KIRO_SKIP=1 git commit ...` bypasses only the kiro hooks,
  unlike `--no-verify`.
