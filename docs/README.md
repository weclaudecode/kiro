# Catalog Overview

This repo is a **catalog** of kiro-cli configuration artifacts. Nothing here
auto-installs. You pick the artifacts you want and copy them into either
`~/.kiro/` (global, cross-project) or `<some-project>/.kiro/`
(project-scoped) using `scripts/install.sh`, which prompts per artifact.

## What's in here

| Folder | What it holds | Goes to |
|---|---|---|
| `steering/` | Markdown rules with YAML frontmatter — shape every kiro session | `~/.kiro/steering/` or `.kiro/steering/` |
| `agents/` | Custom kiro agents (specialized personas) as JSON | `~/.kiro/agents/` or `.kiro/agents/` |
| `prompts/` | Reusable prompts invoked as `@name` | `~/.kiro/prompts/` or `.kiro/prompts/` |
| `hooks/` | IDE file-event hook samples + a CLI pre-tool hook snippet | `<project>/.kiro/hooks/` (IDE) or pasted into agent JSON (CLI) |
| `mcp/` | `mcp.json` sample with placeholders | `~/.kiro/settings/mcp.json` or `<project>/.kiro/settings/mcp.json` |
| `settings/` | `cli.json` sample (global only) | `~/.kiro/settings/cli.json` |
| `skills/` | Eight stack-specific skills plus `skill-creator` (already structured for direct copy) | `~/.kiro/skills/<name>/` or `.kiro/skills/<name>/` |
| `scripts/` | `install.sh` + `list.sh` + the manifest | run from this repo |

## Picking philosophy

- **Always-on steering:** load `tech.md`, `gitops-workflow.md`,
  `secrets-handling.md`, `aws-security.md` globally. They're the contract
  that should hold across every project.
- **fileMatch steering** (`python-conventions.md`,
  `terraform-conventions.md`, etc.): also load globally — they're inert
  outside their fileMatch glob, so there's no cost to having them loaded.
- **Agents:** opt-in per use case. Install the ones you'll actually invoke
  via `/agent <name>`. Agents reference skills + steering, so install those
  first.
- **Prompts:** install the ones you actually use; clutter in
  `~/.kiro/prompts/` makes `@`-completion noisy.
- **Hooks:** the IDE hooks here are project-scoped (don't auto-format
  every `.tf` file on disk). The CLI secret-scan snippet is a pattern to
  paste into agent JSONs.
- **MCP:** install the `mcp.sample.json` once, then comment out the
  servers you don't use. Populate the `${ENV_VAR}` placeholders via
  `direnv` or your secrets file (see `mcp-guide.md`).
- **Settings:** review `cli.sample.json` before installing — schema may
  vary across kiro versions.

## Deeper reading

- `install.md` — install the kiro CLI on Linux + use this catalog
- `steering-guide.md` — inclusion modes + frontmatter reference
- `agents-guide.md` — kiro agent JSON anatomy + walkthrough
- `mcp-guide.md` — env-var pattern + secret handling + troubleshooting
- `specs/` — design docs for changes to this catalog
