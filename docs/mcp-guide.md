# MCP Guide

`mcp.json` registers Model Context Protocol servers that kiro can call as
tools. The catalog ships `mcp/mcp.sample.json` with the servers our stack
uses regularly — `aws-api`, `context7`, two GitLab servers
(`gitlab-official`, `gitlab`), `terraform`, two Kubernetes/observability
servers (`eks`, `cloudwatch`), and three AWS cost servers (`aws-pricing`,
`cost-explorer`, `aws-billing`).

## Install paths

| Path | Scope | Wins on conflict? |
|---|---|---|
| `~/.kiro/settings/mcp.json` | Global | No (workspace overrides) |
| `<project>/.kiro/settings/mcp.json` | Workspace | Yes |

`scripts/install.sh` writes the sample to `settings/mcp.json` (renaming
from `mcp.sample.json`).

## Secret handling — the only rule

**Never hardcode a secret in `mcp.json`.** Use `${ENV_VAR}` placeholders
exclusively. Kiro expands them from the environment at server-spawn time.

Two patterns to populate the env:

### Pattern A — global (cross-project)

`~/.config/claude/secrets.env` (chmod 600), sourced from `~/.zshrc`:

```bash
# ~/.config/claude/secrets.env
export GITLAB_TOKEN="glpat-..."
export CONTEXT7_API_KEY="ctx7_..."
```

```bash
# ~/.zshrc
[ -f ~/.config/claude/secrets.env ] && source ~/.config/claude/secrets.env
```

### Pattern B — per project

`direnv` + a gitignored `.envrc` in each project:

```bash
# <project>/.envrc — gitignored
export AWS_PROFILE=my-project-dev
export AWS_REGION=eu-west-1
export GITLAB_TOKEN="$(pass show gitlab/dev)"
```

```bash
direnv allow
```

## Servers in the sample

| Server | Variables | Purpose | Default |
|---|---|---|---|
| `aws-api` | `AWS_REGION`, `AWS_PROFILE` | AWS CLI-style calls via the AWS Labs MCP | on |
| `context7` | `CONTEXT7_API_KEY` | Up-to-date library/framework docs (preferred over training data) | on |
| `gitlab-official` | `GITLAB_HOST` | **GitLab's first-party MCP** (Premium/Ultimate). Issues, MRs, pipelines via OAuth | **off** |
| `gitlab` | `GITLAB_TOKEN`, `GITLAB_API_URL` | Community PAT-based GitLab MCP — fallback for Free tier | on |
| `terraform` | (none) | **AWS Labs** Terraform MCP — AWS best-practice docs + module/provider lookup + Checkov scan | on |
| `eks` | `AWS_REGION`, `AWS_PROFILE` | Inspect/diagnose EKS clusters + K8s workloads (read-only) | on |
| `cloudwatch` | `AWS_REGION`, `AWS_PROFILE` | Metrics, alarms, Logs Insights for troubleshooting (read-only) | on |
| `aws-pricing` | `AWS_REGION`, `AWS_PROFILE` | AWS list/unit pricing for **estimates**. Calls are **free**. | on |
| `cost-explorer` | `AWS_REGION`, `AWS_PROFILE` | **Actual** spend (narrow). **$0.01 per Cost Explorer API call.** | **off** |
| `aws-billing` | `AWS_REGION`, `AWS_PROFILE` | **Actual** spend + optimization (broad: Cost Optimization Hub, Compute Optimizer, anomalies). Billable. | **off** |

To turn one off, set `"disabled": true` in its block, or remove the block.

### GitLab: official vs community

The sample ships **two** GitLab servers. On **Premium/Ultimate** prefer
`gitlab-official` — GitLab's first-party MCP at
`https://<host>/api/v4/mcp`, available on GitLab.com, Self-Managed, and
Dedicated. It authenticates with **OAuth 2.0 Dynamic Client
Registration** (no PAT in config): on first connect run `/mcp` in the
session and complete the browser authorization. The sample wires it via
`mcp-remote` (needs Node 20+) so it works even where only stdio transport
is available; if your kiro version supports native HTTP MCP you can
instead use a `{ "type": "http", "url": "https://<host>/api/v4/mcp" }`
block. It ships **disabled** — set `GITLAB_HOST`, flip `disabled:false`,
and authenticate.

The community `gitlab` server (`@modelcontextprotocol/server-gitlab`,
PAT-based) stays as the **Free-tier fallback**. Run one or the other, not
both.

### Kubernetes / EKS

`eks` (`awslabs.eks-mcp-server`) is the EKS-native server the
`eks-troubleshooter` agent uses — pods, deployments, events, logs, plus
AWS↔Kubernetes correlation. It is **read-only by default**; cluster
mutation requires the server's `--allow-write` flag, which the sample
**intentionally omits**. For non-EKS / vanilla clusters, a generic server
such as `containers/kubernetes-mcp-server` (talks to the API directly, no
`kubectl` dependency) is the equivalent — add it the same way.

`cloudwatch` (`awslabs.cloudwatch-mcp-server`) is the observability
companion: metrics, alarms, and Logs Insights for incident triage. Both
are read-only and ship enabled.

### The cost servers

The `aws-cost-analyst` agent uses these (it inherits `mcp.json` via
`includeMcpJson: true`). They split by *free estimates* vs *billable
actuals*:

- **`aws-pricing`** answers *"what would X cost?"* — list/unit prices. All
  calls are **free**, so its read tools are in `autoApprove`. Enabled by
  default.
- **`cost-explorer`** answers *"what did environment Y actually spend?"* —
  real billing data. **Every Cost Explorer API request bills $0.01.** It
  therefore ships **`disabled: true`** (opt in deliberately) and with an
  **empty `autoApprove`** so every billable call prompts. Group queries by
  the `Environment` tag and use monthly granularity — see the
  `powerpipe-reporting` skill's `cost-reporting` reference.
- **`aws-billing`** is the **broader** actuals/optimization server
  (`awslabs.billing-cost-management-mcp-server`): it bridges Cost
  Explorer, Cost Optimization Hub, Compute Optimizer, Savings Plans,
  Budgets, S3 Storage Lens, and Cost Anomaly Detection. Its
  Cost-Explorer-backed tools are **also billable** at $0.01/call, so it
  ships `disabled: true` with empty `autoApprove`. **Enable either
  `cost-explorer` or `aws-billing`, not both** — `aws-billing` supersedes
  the narrow one when you want optimization recommendations, not just raw
  spend.

### Terraform: AWS Labs vs HashiCorp

The sample's `terraform` server is the **AWS Labs** one
(`awslabs.terraform-mcp-server`): AWS-on-Terraform best-practice docs,
registry lookup, and a built-in **Checkov** scan (`RunCheckovScan`, needs
`terraform` + `checkov` on `PATH`). HashiCorp also ships an official
`hashicorp/terraform-mcp-server` focused on the **Terraform Registry** and
**HCP Terraform / Enterprise** workspace management. They're
complementary: keep the AWS Labs one for IaC review/scanning; add the
HashiCorp one if you manage HCP workspaces. HashiCorp's docs warn it
"should not be used with untrusted MCP clients or LLMs" — see the security
note below.

## `autoApprove` — what to allow without prompting

Each server can list tool names that auto-approve. Keep this tight:

- Safe to auto-approve: read-only tools (`get_*`, `list_*`, `search_*`,
  `resolve-library-id`, `get-library-docs`, `call_aws` for read-only API
  calls).
- **Never auto-approve** a server's write/mutate tools. The default of
  prompting is a feature.

> `autoApprove` is the field this `mcp.json` sample uses to trust a
> server's tools without prompting. In the agent JSON schema the
> equivalent is `allowedTools` (with `@server/tool` globs like
> `"@eks/list_*"`). Same idea — keep both tight.

## Security: treat MCP tool output as untrusted

An MCP server can return text the model then acts on — which makes tool
output an **injection surface** (a malicious issue body, a poisoned log
line, or a crafted Terraform module README can carry "ignore your
instructions and run …"). Defend in layers:

- **Only install servers you trust.** Prefer first-party servers
  (`awslabs.*`, GitLab's `gitlab-official`, `hashicorp/*`) over random npm
  packages. Pin versions where you can.
- **Least privilege at the credential layer, not just kiro.** The
  read-scoped `GITLAB_TOKEN`, the AWS profile behind `aws-api`/`eks`, and
  the EKS server's omitted `--allow-write` are the real boundaries — a
  prompt-injected tool call still can't exceed the IAM/token it runs as.
- **Keep mutating tools out of `autoApprove`** so a hijacked turn can't
  silently write.
- **Secrets via `${ENV_VAR}` only** (above) so they never sit in a config
  the agent can read back out.
- In headless/CI runs, scope `--trust-tools` narrowly and run in a
  throwaway container — see `headless-guide.md`.

## Troubleshooting

- **Server not appearing in `/tools`:** check `kiro-cli` log
  (`$TMPDIR/kiro-log`). Common cause: missing env var → server crashes on
  spawn.
- **`${VAR}` not expanding:** kiro CLI vs IDE differ on env handling
  (kirodotdev/Kiro #3909). Confirm the var is exported in the shell that
  launched kiro.
- **Workspace overriding unexpectedly:** kiro merges global + workspace,
  workspace wins per server name. Rename a server to keep both.

## See also

- Catalog sample: `../mcp/mcp.sample.json`
- Kiro CLI docs: <https://kiro.dev/docs/cli/mcp/configuration/>
