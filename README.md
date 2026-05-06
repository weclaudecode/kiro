# kiro config catalog

A catalog of [kiro CLI](https://kiro.dev/docs/cli/) configuration
artifacts — steering files, custom agents, prompts, hooks, MCP samples,
and skills — for an AWS / Lambda / Python / Terraform / Terragrunt /
GitLab CI stack.

Nothing here auto-installs. Pick what you want with `scripts/install.sh`,
which prompts per artifact.

## Quick start (Linux)

```bash
git clone git@github.com:weclaudecode/kiro.git ~/code/kiro
cd ~/code/kiro
./scripts/list.sh                 # see what's available
./scripts/install.sh --dry-run    # preview install actions
./scripts/install.sh              # interactive: Y/N per artifact
```

## What's in here

| Folder | Type | Goes to |
|---|---|---|
| `steering/` | Markdown rules with YAML frontmatter | `~/.kiro/steering/` or `<project>/.kiro/steering/` |
| `agents/` | Custom kiro agents (JSON) | `~/.kiro/agents/` or `<project>/.kiro/agents/` |
| `prompts/` | Reusable prompts (`@name`) | `~/.kiro/prompts/` or `<project>/.kiro/prompts/` |
| `hooks/` | IDE file-event hooks + a CLI snippet | `<project>/.kiro/hooks/` (IDE) / agent JSON (CLI) |
| `mcp/` | `mcp.json` sample | `~/.kiro/settings/mcp.json` |
| `settings/` | `cli.json` sample | `~/.kiro/settings/cli.json` |
| `skills/` | Eight stack-specific skills | `~/.kiro/skills/<name>/` |
| `scripts/` | `install.sh`, `list.sh`, `manifest.txt` | runs from this repo |

## Documentation

- [`docs/README.md`](docs/README.md) — catalog overview & picking philosophy
- [`docs/install.md`](docs/install.md) — install kiro CLI + use this catalog
- [`docs/steering-guide.md`](docs/steering-guide.md) — steering inclusion modes
- [`docs/agents-guide.md`](docs/agents-guide.md) — kiro agent anatomy
- [`docs/mcp-guide.md`](docs/mcp-guide.md) — MCP setup & secret handling
- [`docs/specs/`](docs/specs/) — design docs for changes to this catalog

## Conventions in one paragraph

Stack: AWS, Python 3.12 on Lambda (`arm64`), Terraform `>= 1.7` +
Terragrunt `>= 0.55`, GitLab CI with OIDC to AWS, GitOps. No long-lived
AWS keys. No secrets in git. Powertools-first Lambda handlers. Read the
files in `steering/` for the full picture.
