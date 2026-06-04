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
| `eks-troubleshooter` | **Pulls** Kubernetes/EKS evidence via `kubectl` (GET-only) + EKS/CloudWatch MCP and reports root cause | `read`, `shell`, `use_aws`, `@git` | no |
| `platform-orchestrator` | Delegates a multi-faceted review to specialist agents as **subagents** and merges findings (kiro ≥ 1.23) | `read`, `@git`, `subagent` | no |
| `doc-updater` | Proposes README/docs patches from a diff (unified diffs as output — never applied) | `read`, `@git` | no |
| `steering-curator` | Keeps `.kiro/steering/` conventions in sync (proposes unified diffs — never applied) | `read`, `@git` | no |

"Mutates? no" means the agent never changes files, the repo, or any
remote. Most achieve this structurally (no `write`, no auto-approved
`shell`); `gitlab-ci-troubleshooter` and `eks-troubleshooter` auto-approve
`shell` for autonomy but are held read-only by their prompt **and** by
`toolsSettings` command gating (GET-only `glab`/`kubectl`, read-only git,
no `write` tool). "prompts" means writes/commands are possible but never
auto-approved.

Two agents added in this revision show the newer surface:
`eks-troubleshooter` uses `toolsSettings.execute_bash` to hard-gate
`kubectl` to read verbs, and `platform-orchestrator` uses the `subagent`
tool to fan a review out to the specialist agents (see
[`../docs/agents-guide.md`](../docs/agents-guide.md) → Fine-grained gating
and Subagents).

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

- `tools` and `allowedTools` are both `["read", "shell", "@git"]` — there
  is **no `write` tool**, so the agent can never edit files, and `shell`
  is auto-approved so it pulls evidence without a prompt on every `glab`
  call.
- Read-only is enforced by the **prompt**: a **GET-only `glab`**
  allow/forbid list (no `ci run|retry|cancel|delete`, no
  `mr create|merge|approve`, no `api -X POST|PUT|DELETE|PATCH`) and
  **read-only git** (no commit/push/checkout/reset). Fixes are proposed,
  never applied.

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

## `eks-troubleshooter`

The Kubernetes/EKS analogue of `gitlab-ci-troubleshooter`: an **active,
strictly read-only** investigator. Give it a symptom and it pulls the
evidence itself and reports the root cause — it never applies, deletes,
scales, patches, edits, cordons, drains, or `exec`s.

### What it does

1. **Preflight** — checks `kubectl`, prints the current context, and asks
   before touching anything that looks like prod.
2. **Triage** — non-running pods + recent warning events, cluster-wide or
   scoped to a namespace.
3. **Drill in** — `describe` / `logs --previous` / `-o yaml` on the
   suspect object; walks Deployment → ReplicaSet → Pod.
4. **Classify** — OOMKilled (137) · CrashLoopBackOff · ImagePullBackOff ·
   Pending/Unschedulable · CreateContainerConfigError · readiness/probe ·
   node NotReady.
5. **AWS correlation** — IRSA role/trust on the ServiceAccount, node-group
   health, load balancer/target groups via the `eks` MCP and read-only
   `use_aws`; application logs/metrics via the `cloudwatch` MCP.
6. **Report** — TL;DR + confidence, quoted evidence, root cause, a
   **proposed** fix (manifest field / IRSA change), and the read-only
   commands to reproduce.

### Read-only guarantees (defense in depth)

- **Prompt:** a GET-only `kubectl` allow/forbid list and read-only git.
- **`toolsSettings.execute_bash`:** `kubectl` is regex-gated to
  `get|describe|logs|top|explain|...` and **denies**
  `apply|delete|edit|patch|scale|rollout|cordon|drain|exec|...`, with
  `denyByDefault: true`. `use_aws` is `autoAllowReadonly` and denies
  `kms`/`secretsmanager`.
- **No `write` tool** — it can never edit files.
- The real backstop is still least-privilege kube RBAC + IAM; the EKS MCP
  server runs without `--allow-write`.

### Requirements

- `kubectl` on `PATH` with a context for the target cluster (`aws eks
  update-kubeconfig` / OIDC — no long-lived tokens).
- The `eks` and `cloudwatch` MCP servers enabled in `mcp.json`
  (`includeMcpJson: true`).

### Usage

```
/agent eks-troubleshooter
> Pods in the data namespace keep restarting — why?
```

Or headless (nightly snapshot):

```
skills/kubernetes-eks/scripts/triage.sh \
  | kiro-cli chat --no-interactive --agent eks-troubleshooter \
      --trust-tools=read "Summarize cluster health and likely causes."
```

### Loaded context

- `skill://.kiro/skills/kubernetes-eks/SKILL.md`
- `file://.kiro/steering/kubernetes-conventions.md`
- `file://.kiro/steering/aws-security.md`

## `platform-orchestrator`

A read-only **review coordinator** that delegates to the specialist agents
as **subagents** (kiro CLI ≥ 1.23). Hand it a change that spans IaC,
security, cost, pipelines, and Kubernetes; it routes each facet to the
right specialist (`terraform-reviewer`, `security-auditor`,
`aws-cost-analyst`, `gitlab-ci-troubleshooter`, `eks-troubleshooter`),
runs them concurrently, de-duplicates overlap, and merges one prioritized
report. It and every subagent are read-only — findings are proposed, never
applied. If the installed CLI lacks subagent support it says so and falls
back to recommending the specialists individually. See
[`../docs/agents-guide.md`](../docs/agents-guide.md) → Subagents.

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
