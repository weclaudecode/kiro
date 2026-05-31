# kiro config catalog — agents

A kiro agent is a JSON file defining a focused assistant: a system
`prompt`, a tool allow-list (`tools` / `allowedTools`), and preloaded
`resources` (skills + steering). This folder collects the agents in this
catalog. See [`../docs/agents-guide.md`](../docs/agents-guide.md) for the
anatomy and the field reference.

Install one with `scripts/install.sh` (it lands in `~/.kiro/agents/` or
`<project>/.kiro/agents/`), then invoke it from chat with `/agent <name>`.

## Agents in this catalog

| Agent | What it's for | Tools | Mutates? |
|---|---|---|---|
| `aws-architect` | AWS architecture advice: topology, service selection, network/security | `read`, `@mcp` | no |
| `terraform-reviewer` | Senior IaC review of Terraform + Terragrunt diffs | `read`, `shell`, `@git` | no |
| `security-auditor` | Security review of AWS IaC + Python (IAM, exposure, secrets) | `read`, `@git` | no |
| `mr-reviewer` | Pre-merge diff review, emits JSONL findings | `read`, `@git` | no |
| `gitlab-ci-engineer` | Builds/reviews `.gitlab-ci.yml` pipelines for AWS | `read`, `write`, `shell` | yes (prompts) |
| `pipeline-troubleshooter` | Diagnoses a **pasted** CI trace, emits root-cause JSON (cron-friendly) | `read` | no |
| `gitlab-ci-troubleshooter` | **Pulls** a failing pipeline's logs via `glab` and reports the root cause | `read`, `shell`, `@git` | no |
| `powerpipe-report-author` | Authors/runs Powerpipe dashboards + benchmarks over Steampipe, per environment | `read`, `write`, `shell` | yes (prompts) |
| `aws-cost-analyst` | FinOps: estimates (Pricing MCP) + actual per-env spend (Cost Explorer MCP) + waste→savings | `read`, `@mcp` | no |
| `python-lambda-author` | Scaffolds Powertools Lambda handlers, tests, packaging | `read`, `write`, `shell` | yes (prompts) |
| `doc-updater` | Proposes README/docs patches from a diff | `read`, `write`, `@git` | yes (prompts) |
| `steering-curator` | Keeps `.kiro/steering/` conventions in sync | `read`, `write`, `@git` | yes (prompts) |

"Mutates? no" means the agent only ever reads — it has neither `write`
nor an auto-approved `shell`, so it cannot change files, the repo, or any
remote. "prompts" means writes/commands are possible but never
auto-approved.

## `gitlab-ci-troubleshooter`

An **active, strictly read-only** GitLab CI/CD failure investigator. Hand
it a failing pipeline and it pulls the evidence itself, finds the root
cause, and reports it — it never edits, pushes, reruns, retries, or
cancels anything.

It pairs with `pipeline-troubleshooter`: that one is *passive* (you paste
a trace, it returns root-cause JSON — handy for headless cron triage);
this one is *active* (you give it a URL, it fetches the traces) and
writes a human-readable report.

### What it does

1. **Preflight** — checks `glab` is installed and `glab auth status` is
   authenticated (read scopes only); stops with guidance if not.
2. **Parse input** — a pipeline URL, a job URL, an MR URL, or an explicit
   project + pipeline id (self-hosted hosts supported via the URL host /
   `GITLAB_HOST`).
3. **Pull evidence** — pipeline status, the failed jobs, their raw
   traces, and any failed child/downstream (`bridges`) pipelines, all via
   `glab api` (GET only).
4. **Isolate the cause** — the earliest-stage job with `status=failed`
   and `allow_failure=false`; downstream/cancelled jobs are
   de-prioritized.
5. **Classify** — *real* (tests/build/lint/type) → fix code · *config*
   (bad `.gitlab-ci.yml`, missing var/secret, image, `needs`, cache) →
   fix pipeline · *flaky/infra* (timeout, OOM/exit 137, no-space,
   registry/network, lost runner) → retry candidate.
6. **Correlate with code** — the triggering commit/MR diff, a comparison
   against the last green pipeline on the ref, and the offending source
   (local checkout or fetched at the pipeline SHA).
7. **Report** — TL;DR + confidence, a failed-jobs table, quoted log
   evidence, the root cause, a *proposed* fix, and the read-only commands
   to reproduce.

### Requirements

- [`glab`](https://gitlab.com/gitlab-org/cli) on `PATH`
  (`brew install glab`, `apt install glab`, or a release binary).
- A GitLab token with **read** scopes only (`read_api`,
  `read_repository`), via `glab auth login` or `GITLAB_TOKEN` / `GL_TOKEN`
  (plus `GITLAB_HOST` for self-hosted).

### Read-only guarantees

- `tools: ["read", "shell", "@git"]` with only `["read", "@git"]` in
  `allowedTools` — so **every `glab`/shell command prompts** before it
  runs. Nothing executes silently.
- The prompt enforces a **GET-only `glab`** allow/forbid list (no
  `ci run|retry|cancel|delete`, no `mr create|merge|approve`, no
  `api -X POST|PUT|DELETE|PATCH`) and **read-only git** (no
  commit/push/checkout/reset). Fixes are proposed, never applied.

### Usage

```
/agent gitlab-ci-troubleshooter
> Why did https://gitlab.com/acme/web/-/pipelines/12345 fail?
```

Other prompts it handles:

- "This MR pipeline is red — find the root cause."
- "Is this failure flaky/infra or a real test failure?"
- "Compare this failed pipeline to the last green one on the same branch."

### Loaded context

- `skill://.kiro/skills/gitlab-pipeline/SKILL.md`
- `file://.kiro/steering/gitlab-ci-conventions.md`

## Conventions in one paragraph

Each agent is a single JSON file under `~/.kiro/agents/<name>.json`
(global) or `<project>/.kiro/agents/<name>.json` (project); `name` must
match the filename. Keep `prompt` short and push depth into `resources`
(skills + steering). Keep `allowedTools` tight — never auto-approve
`shell` or `write`, so reviews/investigations can't mutate anything by
surprise. Pick the smallest tool set that does the job.

## See also

- [`../docs/agents-guide.md`](../docs/agents-guide.md) — agent anatomy, field reference, patterns
- [`../docs/README.md`](../docs/README.md) — catalog overview
- [`../skills/README.md`](../skills/README.md) — the skills agents load via `resources`
