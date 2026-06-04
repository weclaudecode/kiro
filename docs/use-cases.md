# Use Cases

How to drive this catalog for the day-to-day work on an AWS / Lambda /
Python / Terraform / Terragrunt / GitLab CI / **Kubernetes (EKS)** stack.
Each row points at the agent, skill, MCP server(s), and — where it fits —
the headless invocation. Agents are invoked interactively with
`/agent <name>`; the same agents run in CI via `--no-interactive --agent`
(see `headless-guide.md`).

## At a glance

| I want to… | Agent | Skill(s) | MCP | Headless? |
|---|---|---|---|---|
| Build/refactor a GitLab pipeline | `gitlab-ci-engineer` | `gitlab-pipeline` | `gitlab-official` | — |
| Find why a pipeline failed (have URL) | `gitlab-ci-troubleshooter` | `gitlab-pipeline` | `gitlab-official` | ✔ |
| Triage a pasted CI log | `pipeline-troubleshooter` | `gitlab-pipeline` | — | ✔ (cron) |
| Design/scale AWS architecture | `aws-architect` | `aws-solution-architect` | `aws-api`, `cloudwatch` | — |
| Review Terraform/Terragrunt | `terraform-reviewer` | `terraform-aws`, `terragrunt-multi-account` | `terraform` | ✔ |
| Write a new TF module | (prompt) `@new-terraform-module` | `terraform-aws` | `terraform` | — |
| Estimate / optimize AWS cost | `aws-cost-analyst` | `powerpipe-reporting` | `aws-pricing` (free), `aws-billing`/`cost-explorer` (paid) | ✔ (estimates) |
| Debug an EKS/K8s workload | `eks-troubleshooter` | `kubernetes-eks` | `eks`, `cloudwatch` | ✔ |
| Write a Lambda handler | `python-lambda-author` | `python-lambda`, `python-devops-aws` | — | — |
| Write an AWS automation script | (prompt) `@new-lambda` / ad-hoc | `python-devops-aws` | `aws-api` | — |
| Security review a change | `security-auditor` | `security-code-reviewer` | `terraform` (Checkov) | ✔ |
| Review an MR end-to-end | `mr-reviewer` | (diff-driven) | — | ✔ |
| Coordinate a multi-faceted review | `platform-orchestrator` | (delegates) | — | — |
| Inventory / audit the estate | (Steampipe) | `steampipe`, `powerpipe-reporting` | — | ✔ (cron) |

## By task

### GitLab CI: create & troubleshoot
- **Create/refactor:** `/agent gitlab-ci-engineer` — builds
  `.gitlab-ci.yml` with `workflow:rules`, OIDC-to-AWS auth, DAG `needs`,
  per-environment deploys. Backed by the `gitlab-pipeline` skill's
  templates.
- **Troubleshoot (have a URL):** `/agent gitlab-ci-troubleshooter` pulls
  the failed job traces itself via `glab` (GET-only) and reports the root
  cause. Read-only.
- **Triage a pasted/streamed log (CI/cron):** `pipeline-troubleshooter`
  emits root-cause JSON from a log on stdin — see the
  `kiro-pipeline-triage` job in `headless/gitlab-ci.sample.yml`.
- On Premium/Ultimate, enable the `gitlab-official` MCP so agents can read
  issues/MRs/pipelines directly.

### AWS architecture & troubleshooting
- **Design:** `/agent aws-architect` (Well-Architected framing, service
  selection, topology). MCP: `aws-api` for live state, `cloudwatch` for
  metrics/logs during incident triage.
- **Cost-aware design:** chain to `aws-cost-analyst` for a $/month
  estimate before committing (free Pricing MCP).

### Cost optimization
- `/agent aws-cost-analyst`. **Estimates** (`aws-pricing`) are free —
  use freely, including headless. **Actuals** (`cost-explorer` or the
  broader `aws-billing`) bill **$0.01/call** and ship `disabled`; the
  agent announces billable calls and groups by the `Environment` tag.
  `aws-billing` adds Cost Optimization Hub / Compute Optimizer
  recommendations. Turn idle resources found by `powerpipe-report-author`
  into a ranked savings list.

### Terraform / Terragrunt
- **Author:** prompt `@new-terraform-module`; skill `terraform-aws`.
- **Review:** `/agent terraform-reviewer` — read-mostly; `shell` is gated
  by `toolsSettings` to `plan`/`validate`/`fmt` and **denies `apply`**, so
  a review can't mutate state. The `terraform` MCP adds a Checkov scan.
- **Multi-account orchestration:** skill `terragrunt-multi-account`.

### Kubernetes / EKS
- **Debug a symptom:** `/agent eks-troubleshooter` — pulls evidence via
  `kubectl` (GET/describe/logs only, enforced by `toolsSettings`) plus the
  `eks` + `cloudwatch` MCP servers, classifies (OOMKilled / CrashLoop /
  ImagePull / Pending / IRSA), and proposes a fix. Never mutates.
- **Design/harden manifests:** skill `kubernetes-eks` + the
  `kubernetes-conventions` steering (limits, probes, IRSA, securityContext,
  NetworkPolicy).
- **Headless health snapshot:** pipe
  `skills/kubernetes-eks/scripts/triage.sh` into
  `--no-interactive --agent eks-troubleshooter` (nightly job included in
  the CI sample).

### Python
- **Lambda:** `/agent python-lambda-author` (Powertools handlers, tests,
  packaging) — skills `python-lambda` → `python-devops-aws`.
- **Automation scripts:** skill `python-devops-aws` (boto3, assume-role,
  retries, pagination); `aws-api` MCP for live calls.

### Security (every layer)
- **Review:** `/agent security-auditor` (IAM, exposure, secrets across IaC
  + Python) — skill `security-code-reviewer`. Run it **after** GitLab
  Ultimate's SAST/SCA/secret-detection, not instead of them.
- **IaC scanning:** the `terraform` MCP's Checkov scan; the
  `cli-pre-tool-secret-scan` hook blocks shell calls that would leak
  secrets.
- **Coordinated review:** `/agent platform-orchestrator` fans a change out
  to terraform-reviewer + security-auditor + aws-cost-analyst as subagents
  and merges the findings.

## GitLab Ultimate: kiro alongside the platform

The two are complementary, not either/or:

- **kiro CLI** — local/terminal authoring + investigation, and the
  headless bot in your own CI jobs (`headless/gitlab-ci.sample.yml`).
- **GitLab Duo with Amazon Q** (requires **Ultimate**) — platform-native
  `/q dev`, `/q review`, automatic MR reviews, and vulnerability-report
  remediation, with single-source audit evidence in the pipeline.
- **GitLab Ultimate scanners** (SAST, DAST, secret detection, dependency
  scanning) run in-pipeline; kiro's `security-auditor` adds the
  hypothesis-driven, business-logic review those scanners miss. Let the
  scanners gate; let kiro explain and prioritize.

## See also

- [`headless-guide.md`](headless-guide.md) — running any of these in CI/cron
- [`agents-guide.md`](agents-guide.md) — agent anatomy, `toolsSettings`, subagents
- [`mcp-guide.md`](mcp-guide.md) — wiring the MCP servers referenced above
- [`../skills/README.md`](../skills/README.md) — the skills index
