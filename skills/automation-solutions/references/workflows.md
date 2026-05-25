# Headless kiro-cli workflows

Every workflow runs kiro non-interactively with `--trust-tools read,grep` so it
can never write code without a human reviewing first. All assume `KIRO_API_KEY`
is exported, `kiro-cli` is on `PATH`, and the agents below live in
`~/.kiro/agents/` or the project's `.kiro/agents/`.

Scripts for the git hooks live in `../scripts/githooks/`; the cron jobs in
`../scripts/cron/`. Wire the hooks into a repo with `../scripts/install-hooks.sh`.

> Flag surface varies by kiro-cli version. These examples use
> `kiro-cli chat --no-interactive ... "<prompt>"`. Confirm the headless flags on
> your build with `kiro-cli chat --help` (some builds expose `kiro-cli -p`).

## Git hooks

### 1. pre-commit — local review before stage leaves disk

Reviews the staged diff with `mr-reviewer` and blocks the commit on any
critical finding.

- **Why:** catches the worst issues at the earliest boundary, before they're
  even committed.
- **Trade-off:** adds ~10-30s per commit. Mitigate with `KIRO_SKIP=1` for WIP
  commits, or push the heavy review out to pre-push (#4).
- **Script:** `scripts/githooks/pre-commit`.

### 2. prepare-commit-msg — conventional-commit drafts from the diff

Drafts a conventional-commit message from the staged diff and prepends it to
the commit template; you edit it in your editor. Your own `-m`/`-F` message
always wins.

- **Trade-off:** every interactive commit pays the latency. Skip with
  `KIRO_SKIP=1` or by passing `-m`. Some teams prefer to *validate* the message
  rather than generate it — see #2b.
- **Script:** `scripts/githooks/prepare-commit-msg`.

### 2b. commit-msg — conventional-commit validator (added)

A pure-local regex gate (no API call, zero cost) that rejects commit subjects
that aren't conventional commits. Complements the generator in #2: generate on
the way in, validate on the way out. Merge/revert/fixup subjects are exempt.

- **Script:** `scripts/githooks/commit-msg`.

### 3. post-commit — async doc sync from the diff

Fires in the background after each commit so it never slows you down. Asks
`doc-updater` which docs (AGENTS.md, README.md, docs/**) the commit made stale
and emits unified diffs to `$TMPDIR/doc-patches-<sha>.patch`.

- **Trade-off:** proposals only — never auto-apply (that's what preserves the
  review value). Review the queued patch with `git apply --check` before using.
- **Harden:** give `doc-updater` an `allowedPaths` restricted to docs so it
  can't wander.
- **Script:** `scripts/githooks/post-commit`.

### 4. pre-push — heavier review + security scan before the MR

Runs `security-auditor` over the full `upstream...HEAD` diff and blocks the push
on any critical/BLOCK finding.

- **Why:** the best-ROI hook of the set — it catches issues at the natural
  "leaving local" boundary, and only fires on push.
- **Trade-off:** slower (~30-90s), but infrequent. Bypass with `KIRO_SKIP=1`.
- **Script:** `scripts/githooks/pre-push`.

## Scheduled jobs (cron / timers)

You can read pipelines locally but not run kiro inside CI, so pull artifacts
down and analyze them on a schedule. See `scheduling.md` for cron vs. systemd
timers vs. launchd vs. EventBridge.

### 5. Nightly pipeline triage

Pulls the last 24h of failed GitLab pipelines via `glab`, traces each, and asks
`pipeline-troubleshooter` for a root cause. Emails the digest.

- **Trade-off:** needs a long-running host (laptop, a `t4g.nano`, or a home
  server). For solo ops a `t4g.nano` + EventBridge Scheduler beats crontab.
- **Script:** `scripts/cron/kiro-pipeline-triage.sh`.

### 6. Nightly dependency / CVE scan (added)

Runs `pip-audit` and `trivy fs`, then has kiro triage the raw output into a
severity-grouped digest with concrete upgrade commands — exploitability judged
in this repo's context, not just raw CVSS.

- **Script:** `scripts/cron/kiro-dependency-scan.sh`.

### 7. Weekly steering refresh (added)

Summarizes the last 7 days of commits and asks `steering-curator` to propose
edits to `.kiro/steering/` as unified diffs, so project context doesn't drift.
Proposes only — never applies.

- **Script:** `scripts/cron/kiro-steering-refresh.sh`.

## Agents these workflows invoke

| Agent | Role | Catalog file |
| --- | --- | --- |
| `mr-reviewer` | Read-only diff reviewer, JSONL findings (pre-commit) | `agents/mr-reviewer.json` |
| `security-auditor` | Read-only security scan (pre-push) | `agents/security-auditor.json` |
| `doc-updater` | Read-only doc-sync, proposes diffs (post-commit) | `agents/doc-updater.json` |
| `pipeline-troubleshooter` | Read-only CI failure diagnosis (cron) | `agents/pipeline-troubleshooter.json` |
| `steering-curator` | Read-only steering maintainer (cron) | `agents/steering-curator.json` |

Install them with `scripts/install.sh` (they're registered in the manifest).
