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
| `tools` | Tool families this agent can use: `read`, `write`, `shell`, `web`, `@git`, `@mcp`, `*` |
| `allowedTools` | Subset of `tools` that auto-approve (no per-call prompt). Keep this tight — `read` and `@git` are usually safe. |
| `resources` | Files/skills preloaded into the agent's context every session. URIs: `file://`, `skill://`. |
| `mcpServers` | Per-agent MCP server overrides. Usually omitted; rely on `includeMcpJson`. |
| `includeMcpJson` | If true, this agent inherits the workspace/global `mcp.json`. |
| `hooks` | Pre/post tool-use hooks (CLI hooks live HERE, not in `.kiro/hooks/`). |
| `toolsSettings.subagent` | Sub-agent allow-list — agents this agent can dispatch to. |

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
