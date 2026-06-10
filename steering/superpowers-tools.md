---
inclusion: always
---

# Superpowers → kiro tool mapping

The `superpowers` skill bundle (`.kiro/skills/superpowers/`) is ported from
[obra/superpowers](https://github.com/obra/superpowers), a methodology
written for **Claude Code**. Its skill text uses Claude Code tool names and
idioms. When a superpowers skill (or any imported skill) tells you to use a
Claude Code tool, **translate it to the kiro equivalent in this table before
acting**. Same intent, kiro verb.

## Tool name mapping

| Claude Code tool / idiom | kiro CLI equivalent | Notes |
|---|---|---|
| `Read` | `fs_read` (alias `read`) | Read a file or list a directory. |
| `Glob` | `fs_read` | kiro's read tool globs/lists; or `execute_bash` (`rg --files`, `find`). |
| `Grep` | `fs_read` (search) | or `execute_bash` (`rg`, `grep`). |
| `Edit` / `MultiEdit` | `fs_write` (alias `write`) | kiro `fs_write` does targeted string-replace edits. |
| `Write` | `fs_write` | Create or overwrite a file. |
| `NotebookEdit` | `fs_write` | Edit notebook cells as text. |
| `Bash` | `execute_bash` (alias `shell`) | Run a shell command. |
| `Task` / "dispatch a subagent" | `subagent` tool, invoked as `/agent <name>` | Delegate to a custom kiro agent (up to 4 concurrent). See `docs/agents-guide.md`. |
| `Skill` / "invoke the X skill" | `fs_read` on `.kiro/skills/<x>/SKILL.md`, or `/<x>` if installed as manual steering | kiro has no `Skill` tool; load a skill by reading its `SKILL.md`. |
| `TodoWrite` | *(no native tool)* | Track tasks as `- [ ]` checkboxes in the plan file under `docs/superpowers/plans/`. |
| `WebFetch` / `WebSearch` | `@web` (web tool) | Fetch or search the web. |
| `SlashCommand` | `/<prompt-or-steering-name>` | kiro reusable prompts (`@name`) and manual steering (`/name`). |
| `AskUserQuestion` | plain chat question | Ask the user inline; kiro has no structured-options tool. |
| git via `Bash` | `@git` tool family | kiro exposes git as an MCP-style tool family; plain `execute_bash git …` also works. |

## Cross-skill references

Superpowers skills reference each other as `superpowers:<skill-name>` (e.g.
`superpowers:using-git-worktrees`). In this port those live as sibling files:
read `.kiro/skills/superpowers/references/<skill-name>.md`.

## Announcement convention

Superpowers asks the agent to announce which skill it is using (e.g. "I'm
using the brainstorming skill"). Keep that convention — it makes the active
workflow visible to the user.

## What does NOT translate

- **Subagent isolation.** Claude Code subagents get a fresh context window.
  kiro `subagent`s do too, but inherit the *referenced agent's*
  `tools`/`toolsSettings`. Point them at a real agent in `.kiro/agents/` (or
  the `subagent` tool's ad-hoc form), not at a Claude Code "general-purpose"
  type that does not exist here.
- **Plugin/marketplace install.** Ignore superpowers' Claude Code plugin
  install steps. In kiro these skills install via `scripts/install.sh` into
  `~/.kiro/skills/superpowers/`.
