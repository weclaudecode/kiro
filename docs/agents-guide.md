# Agents Guide

Custom kiro agents are JSON files in `~/.kiro/agents/` (global) or
`<project>/.kiro/agents/` (project). They're invoked from the chat with:

```
/agent terraform-reviewer
```

A kiro agent is roughly: a system prompt, a tool allow-list, a set of
preloaded resources (skills, steering files, ad-hoc files), and optional
hooks/MCP wiring.

## Anatomy

```json
{
  "name": "terraform-reviewer",
  "description": "Senior IaC reviewer for AWS Terraform + Terragrunt.",
  "model": "claude-sonnet-4-6",
  "prompt": "You are a senior infrastructure reviewer...",
  "tools": ["read", "shell", "@git"],
  "allowedTools": ["read", "@git"],
  "resources": [
    "skill://.kiro/skills/terraform-aws/SKILL.md",
    "file://.kiro/steering/terraform-conventions.md"
  ],
  "mcpServers": { },
  "includeMcpJson": false
}
```

### Field reference

| Field | Purpose |
|---|---|
| `name` | The slug used in `/agent <name>`. Must match the filename without `.json`. |
| `description` | One sentence that helps you (and kiro) pick this agent. |
| `model` | Override the default model for this agent. Optional. |
| `prompt` | The system prompt. Inline string, or `"file:///abs/path/PROMPT.md"`. |
| `tools` | Tool families this agent can use: `read`, `write`, `shell`, `web`, `@git`, `@mcp`, `subagent`, `*`. (Canonical aliases also accepted: `fs_read`, `fs_write`, `execute_bash`, `use_aws`.) |
| `allowedTools` | Subset of `tools` that auto-approve (no per-call prompt). Keep this tight — `read` and `@git` are usually safe. Supports globs: `"@eks/list_*"`. |
| `toolsSettings` | Per-tool fine-grained allow/deny — path globs, command regexes, AWS service lists. See **Fine-grained gating** below. |
| `resources` | Files/skills preloaded into the agent's context every session. URIs: `file://`, `skill://`. |
| `mcpServers` | Per-agent MCP server overrides. Usually omitted; rely on `includeMcpJson`. |
| `includeMcpJson` | If true, this agent inherits the workspace/global `mcp.json`. |
| `hooks` | Pre/post tool-use hooks — events `agentSpawn`, `userPromptSubmit`, `preToolUse`, `postToolUse`, `stop`. CLI hooks live HERE, not in `.kiro/hooks/`. |
| `keyboardShortcut` | Optional quick-switch binding (e.g. `"ctrl+a"`). |
| `welcomeMessage` | Optional message shown when the agent activates. |

## Walkthrough: anatomy of `terraform-reviewer.json`

```jsonc
{
  "name": "terraform-reviewer",
  "description": "Senior IaC reviewer for AWS Terraform + Terragrunt...",

  // Read-mostly: it should not modify code, only review.
  "tools": ["read", "shell", "@git"],

  // Auto-approve safe ops; shell still prompts so a stray `terraform apply`
  // can't fire silently.
  "allowedTools": ["read", "@git"],

  // Preload the relevant skill + steering files so the agent doesn't have
  // to re-discover conventions every turn.
  "resources": [
    "skill://.kiro/skills/terraform-aws/SKILL.md",
    "skill://.kiro/skills/terragrunt-multi-account/SKILL.md",
    "skill://.kiro/skills/security-code-reviewer/SKILL.md",
    "file://.kiro/steering/terraform-conventions.md",
    "file://.kiro/steering/terragrunt-conventions.md",
    "file://.kiro/steering/aws-security.md"
  ],

  // No MCP — review is a local-only task.
  "includeMcpJson": false
}
```

## Patterns

- **Read-only auditor:** `tools = ["read", "@git"]`, `allowedTools` same.
  No `write`, no `shell`. Use for review/audit agents.
- **Authoring assistant:** `tools = ["read", "write", "shell"]`,
  `allowedTools = ["read"]`. Writes prompt before save; shell prompts
  before run.
- **Architect / advisor:** `tools = ["read", "@mcp"]`. No edits. MCP
  enabled for queries (Steampipe, AWS API, etc.).
- **Autonomous read-only investigator:** `tools = ["read", "shell",
  "@git"]`, `allowedTools` the same. Auto-approves `shell` so it pulls
  its own evidence from a CLI without a prompt per call; stays read-only
  via the prompt (GET-only commands, no `write` tool). See
  `gitlab-ci-troubleshooter` (drives `glab`). Only do this when the
  prompt strictly constrains the CLI to read-only verbs.
- **Cautious reviewer:** `tools = ["read", "shell", "@git"]`,
  `allowedTools = ["read", "@git"]` — `shell` stays out of `allowedTools`
  so a stray mutating command (e.g. `terraform apply`) can't fire
  silently. See `terraform-reviewer`, `security-auditor`.

## Fine-grained gating (`toolsSettings`)

`allowedTools` is binary (prompt / don't prompt). `toolsSettings` adds a
finer layer: which paths a tool may touch, which shell commands may run,
which AWS services it may call. Deny rules evaluate **before** allow.

```jsonc
"toolsSettings": {
  "fs_write": {
    "allowedPaths": ["**/*.tf", "**/*.hcl", "*.py", "k8s/**"],
    "deniedPaths":  ["**/.git/**", "**/secrets.env", "**/*.tfstate"]
  },
  "execute_bash": {
    "allowedCommands": ["terraform (plan|validate|fmt).*", "kubectl (get|describe|logs|top) .*", "checkov .*"],
    "deniedCommands":  ["terraform apply.*", "kubectl delete.*", "sudo .*", "rm -rf .*"],
    "autoAllowReadonly": true,
    "denyByDefault": true
  },
  "use_aws": {
    "allowedServices": ["s3", "eks", "ec2", "iam", "logs", "cloudformation", "ce"],
    "deniedServices":  ["kms", "secretsmanager"],
    "autoAllowReadonly": true
  }
}
```

- `execute_bash` patterns are **regex**; anchor them (`\A…\z`) when you
  need an exact match so `terraform apply-fake` can't slip through a loose
  `terraform apply.*`.
- `autoAllowReadonly` trusts GET-class operations (read-only AWS calls,
  read-only shell) without prompting; pair it with a tight allow-list.

> **Security caveat — don't treat `deniedCommands` as a hard wall.**
> There have been real enforcement bugs where denied commands ran before
> the permission check (Amazon Q issue #2477) and where `allowedPaths`
> didn't suppress prompts (Kiro issue #4212). Use `toolsSettings` as
> defense-in-depth, but put the *real* boundary at the layer below kiro:
> least-privilege IAM / scoped tokens, a `preToolUse` guardrail hook (see
> `hooks/cli-pre-tool-secret-scan.md`), and a throwaway container for
> anything autonomous. Pin a known-good kiro version and test that your
> deny rules actually block.

## Subagents (delegation)

A custom agent can fan work out to focused **subagents** when its `tools`
array includes the `subagent` tool. Subagents run concurrently (up to
four), each loading its own narrow agent config; invoke them by naming the
target agent in the task ("Use the `terraform-reviewer` to check the IaC
diff, and `eks-troubleshooter` for the failing pods"). They inherit the
referenced agent's `tools`/`toolsSettings`/`allowedTools`, so a read-only
subagent stays read-only even when an orchestrator drives it.

```jsonc
{
  "name": "platform-orchestrator",
  "tools": ["read", "@git", "subagent"],
  "allowedTools": ["read", "@git"]
  // prompt routes to terraform-reviewer / eks-troubleshooter /
  // gitlab-ci-troubleshooter / aws-cost-analyst by name
}
```

Use it to run a multi-faceted review (IaC + security + cost) in one pass.
See `../agents/platform-orchestrator.json`. (Subagents are a Kiro-era
feature — kiro CLI ≥ 1.23; `/agent` on older Amazon Q CLI builds won't
have them.)

## Running an agent headlessly

Any agent works in non-interactive mode — pass `--agent` to `chat
--no-interactive`:

```bash
git diff origin/main...HEAD \
  | kiro-cli chat --no-interactive --agent mr-reviewer \
      --trust-tools=read,grep "Review this diff. Emit JSONL findings."
```

This is how the read-only agents (`mr-reviewer`,
`pipeline-troubleshooter`, `eks-troubleshooter`) plug into GitLab CI and
cron. Keep `--trust-tools` to the read class; never `--trust-all-tools` in
a pipeline. Full patterns + auth in `headless-guide.md`.

## Tips

- Keep `prompt` short (one paragraph + one short list). Heavy detail
  belongs in skills or steering, which the agent loads via `resources`.
- Don't grant `write` and put the agent in auto-approve. Combination is a
  silent-edit hazard.
- One skill per agent gives the cleanest mental model. Agents that wire
  in 5+ skills tend to confuse themselves.

## See also

- Catalog agents: `../agents/`
- Kiro CLI docs: <https://kiro.dev/docs/cli/custom-agents/configuration-reference/>
