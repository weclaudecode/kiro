# MCP Guide

`mcp.json` registers Model Context Protocol servers that kiro can call as
tools. The catalog ships `mcp/mcp.sample.json` with the servers our stack
uses regularly — `aws-api`, `context7`, `gitlab`, `terraform`, and two AWS
cost servers (`aws-pricing`, `cost-explorer`).

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

| Server | Variables | Purpose |
|---|---|---|
| `aws-api` | `AWS_REGION`, `AWS_PROFILE` | AWS CLI-style calls via the official AWS Labs MCP |
| `context7` | `CONTEXT7_API_KEY` | Up-to-date library/framework docs (preferred over training data) |
| `gitlab` | `GITLAB_TOKEN`, `GITLAB_API_URL` | Read/write Issues + MRs + pipelines |
| `terraform` | (none) | HashiCorp's official Terraform MCP — module + provider docs |
| `aws-pricing` | `AWS_REGION`, `AWS_PROFILE` | AWS list/unit pricing for **estimates**. Calls are **free**. Enabled. |
| `cost-explorer` | `AWS_REGION`, `AWS_PROFILE` | **Actual** AWS spend. **$0.01 per Cost Explorer API call.** Ships `disabled: true`. |

To turn one off, set `"disabled": true` in its block, or remove the block.

### The two cost servers

The `aws-cost-analyst` agent uses these (it inherits `mcp.json` via
`includeMcpJson: true`). They split cleanly:

- **`aws-pricing`** answers *"what would X cost?"* — list/unit prices. All
  calls are **free**, so its read tools are in `autoApprove`. Enabled by
  default.
- **`cost-explorer`** answers *"what did environment Y actually spend?"* —
  real billing data. **Every Cost Explorer API request bills $0.01.** It
  therefore ships **`disabled: true`** (opt in deliberately) and with an
  **empty `autoApprove`** so every billable call prompts. Group queries by
  the `Environment` tag and use monthly granularity — see the
  `powerpipe-reporting` skill's `cost-reporting` reference.

## `autoApprove` — what to allow without prompting

Each server can list tool names that auto-approve. Keep this tight:

- Safe to auto-approve: read-only tools (`get_*`, `list_*`, `search_*`,
  `resolve-library-id`, `get-library-docs`, `call_aws` for read-only API
  calls).
- **Never auto-approve** a server's write/mutate tools. The default of
  prompting is a feature.

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
