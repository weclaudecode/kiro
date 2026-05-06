# Kiro Config Catalog — Design

**Date:** 2026-05-07
**Status:** Approved (Option B — full catalog)
**Repo:** `weclaudecode/kiro` (this repo)

## Purpose

This repo is a **catalog** of kiro-cli configuration artifacts. The user picks
individual files and copies them into either:

- `~/.kiro/` on their Linux workstation (global, cross-project), or
- `<some-project>/.kiro/` (project-scoped).

Nothing here auto-installs. The bootstrap script is interactive and asks per
artifact.

## Non-goals

- No opinionated "install everything" flow.
- No mirror of the existing `skills/` content (already structured correctly).
- No secrets in any committed file. MCP samples use `${ENV_VAR}` placeholders only.
- No Kiro IDE-specific assumptions beyond what the CLI also honors. IDE-only
  artifacts (file-event hooks) are kept in their own folder and labeled.

## Repo layout

```
agents/             custom kiro agents (*.json)
steering/           steering files (*.md w/ YAML frontmatter)
prompts/            reusable prompts (*.md), invoked as @name
hooks/              IDE hook samples (*.kiro.hook); CLI hook snippets in docs/
mcp/                mcp.json samples (placeholders only)
settings/           cli.json sample
skills/             EXISTING — left as-is (8 skills)
scripts/            install.sh (interactive), list.sh
docs/               guidelines, install, per-feature how-tos
README.md           1-page catalog index pointing into docs/
```

Every artifact file leads with a header comment indicating its install path,
e.g. `# Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/`.

## Inventory

### Steering (`steering/*.md`)

| File | `inclusion` | When it loads |
|---|---|---|
| `tech.md` | always | Every session — declares the stack |
| `gitops-workflow.md` | always | Branch/MR rules |
| `secrets-handling.md` | always | Credential discipline |
| `aws-security.md` | always | IAM least-priv, KMS, networking |
| `python-conventions.md` | fileMatch `**/*.py` | Editing Python |
| `terraform-conventions.md` | fileMatch `**/*.tf` | Editing Terraform |
| `terragrunt-conventions.md` | fileMatch `**/terragrunt.hcl` | Editing Terragrunt |
| `lambda-conventions.md` | fileMatch `**/handler.py`, `**/lambda_function.py` | Lambda handlers |
| `gitlab-ci-conventions.md` | fileMatch `**/.gitlab-ci*.yml` | GitLab CI files |

> Frontmatter convention: `fileMatch` is shorthand. The actual YAML keys are
> `inclusion: fileMatch` and `fileMatchPattern: <glob>` (kiro CLI docs). For
> multiple globs, use a YAML list under `fileMatchPattern`.

### Agents (`agents/*.json`)

| Agent | Skill it composes with | Tools |
|---|---|---|
| `terraform-reviewer.json` | `terraform-aws`, `terragrunt-multi-account` | read, shell, @git |
| `python-lambda-author.json` | `python-lambda` | read, write, shell |
| `gitlab-ci-engineer.json` | `gitlab-pipeline` | read, write, shell |
| `aws-architect.json` | `aws-solution-architect`, `steampipe` | read, @mcp |
| `security-auditor.json` | `security-code-reviewer` | read, shell, @git |

Each agent JSON references its skill via `resources: ["skill://..."]` and
includes a `prompt` that points at a sibling Markdown file when the persona
needs more than a one-paragraph system prompt.

### Prompts (`prompts/*.md`)

- `new-lambda.md` — scaffold handler + tests + IaC stub
- `new-terraform-module.md` — module skeleton (variables/outputs/README)
- `mr-description.md` — generate GitLab MR body from current diff
- `review-iac.md` — Terraform/Terragrunt diff review checklist
- `runbook.md` — operational runbook from a Lambda or service spec

### Hooks (`hooks/`)

- `pre-commit-tf-fmt.kiro.hook` (IDE) — `terraform fmt` + `terragrunt hclfmt` on save
- `pre-commit-py-lint.kiro.hook` (IDE) — `ruff check` on `.py` save
- `cli-pre-tool-secret-scan.md` — JSON snippet to paste into an agent's `hooks`
  block (CLI hooks live inside agent JSON, not as standalone files)

### MCP (`mcp/mcp.sample.json`)

Servers (all secrets via `${ENV_VAR}`):

- `awslabs.aws-api-mcp-server` (AWS official)
- `context7` (library docs)
- `gitlab` (GitLab MCP)
- `terraform` (HashiCorp official)

### Settings (`settings/cli.sample.json`)

- Default model: `claude-sonnet-4-6` (latest stable as of 2026-05-07)
- Theme: dark
- Auto-approval scope: read tools only
- Telemetry: off

### Scripts (`scripts/`)

- `install.sh` — for each artifact, prompts `Install <name> → <dest>? [y/N]`,
  defaults to no, supports `--dry-run` and `--scope global|project <path>`.
- `list.sh` — prints inventory + each artifact's install destination.
- Both scripts use `bash` with `set -euo pipefail` (not strict POSIX sh).

### Docs (`docs/`)

- `README.md` — catalog overview, philosophy, "how to pick"
- `install.md` — install kiro CLI on Linux + how to consume this catalog
- `steering-guide.md` — inclusion modes, frontmatter reference
- `agents-guide.md` — kiro agent JSON anatomy + walkthrough
- `mcp-guide.md` — env-var pattern, secret handling, troubleshooting
- `specs/` — design docs (this file lives here)

### Repo root

- `README.md` rewritten as a 1-page catalog index pointing into `docs/`.

## Conventions

- **No secrets, ever.** All MCP examples use `${ENV_VAR}` placeholders. The
  `mcp-guide.md` documents the user's preferred secrets pattern (`direnv` +
  `~/.config/claude/secrets.env`, per their global CLAUDE.md).
- **Stack-locked content only.** AWS, Lambda, Python 3.12, Terraform,
  Terragrunt, GitLab CI, GitOps. No generic web/frontend artifacts.
- **Each artifact is self-describing** (header comment with install path and
  one-line purpose), so a user reading any single file knows where it goes.
- **Skills stay where they are** at `skills/` (the existing layout already
  matches kiro's `~/.kiro/skills/` and `.kiro/skills/`).

## Out of scope

- Auto-symlinking the whole repo into `~/.kiro/`.
- Project-specific `.kiro/` directories for downstream repos.
- Skill authoring guidelines (the existing 8 skills already exemplify the
  pattern; new skills can copy an existing one).
- Kiro IDE-specific UI configuration.

## Verification

After implementation:

1. `scripts/list.sh` runs and prints all artifacts with destinations.
2. `scripts/install.sh --dry-run --scope global` walks every artifact without
   writing.
3. Every steering `.md` parses as valid YAML frontmatter + Markdown.
4. Every agent `.json` and `mcp.sample.json` parses as valid JSON.
5. `git grep -nE '(AKIA|ASIA|aws_secret|password|token)\s*[:=]'` returns no
   hardcoded secrets.

## Delivery

One commit, pushed to `main` on `origin` (`weclaudecode/kiro`).
