---
inclusion: always
---

<!--
  GENERATED FILE — do not edit by hand.
  Source: skills/using-superpowers/SKILL.md
          skills/using-superpowers/references/kiro-tools.md
  Regenerate: scripts/gen-superpowers-bootstrap.sh
-->

<EXTREMELY_IMPORTANT>
You have superpowers.

**Below is the full content of your `superpowers:using-superpowers` skill — your
introduction to using skills. It is already loaded; do not try to load it again.
Every other skill lives in `.kiro/skills/<name>/SKILL.md` and is activated the
Kiro way: automatic description match, `/skill-name`, or reading its `SKILL.md`
(see the Kiro tool mapping at the end of this file).**


<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. You cannot rationalize your way out of this.
</EXTREMELY-IMPORTANT>

## The Rule

**Invoke relevant or requested skills BEFORE any response or action** — including clarifying questions, exploring the codebase, or checking files. If it turns out wrong for the situation, you don't have to use it.

**Before entering plan mode:** if you haven't already brainstormed, invoke the brainstorming skill first.

Then announce "Using [skill] to [purpose]" and follow the skill exactly. If it has a checklist, create a todo per item.

## Skill Priority

When multiple skills apply, process skills come first — they set the approach, then implementation skills (frontend-design, etc.) carry it out. Brainstorming and systematic-debugging are Superpowers' most common process skills, but the rule holds for any of them.

- "Let's build X" → superpowers:brainstorming first, then implementation skills.
- "Fix this bug" → superpowers:systematic-debugging first, then domain skills.

## Red Flags

These thoughts mean STOP—you're rationalizing:

| Thought | Reality |
|---------|---------|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "I can check git/files quickly" | Files lack conversation context. Check for skills. |
| "Let me gather information first" | Skills tell you HOW to gather information. |
| "This doesn't need a formal skill" | If a skill exists, use it. |
| "I remember this skill" | Skills evolve. Read current version. |
| "This doesn't count as a task" | Action = task. Check for skills. |
| "The skill is overkill" | Simple things become complex. Use it. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |
| "This feels productive" | Undisciplined action wastes time. Skills prevent this. |
| "I know what that means" | Knowing the concept ≠ using the skill. Invoke it. |

## Platform Adaptation

If your harness appears here, read its reference file for special instructions:

- Codex: `references/codex-tools.md`
- Pi: `references/pi-tools.md`
- Antigravity: `references/antigravity-tools.md`
- Kiro: `references/kiro-tools.md`

## User Instructions

User instructions (CLAUDE.md, AGENTS.md, GEMINI.md, etc, direct requests) take precedence over skills, which in turn override default behavior. Only skip skill workflows or instructions when your human partner has explicitly told you to.

---

**Kiro tool mapping — how the actions the skills ask for map to Kiro's real
tools. This is the platform adaptation referenced by "Platform Adaptation" above.**

# Kiro Tool Mapping

Skills speak in actions ("read a file", "dispatch a subagent", "create a todo",
"invoke a skill"). On **Kiro** (`kiro-cli` and Kiro IDE) those actions resolve to
the built-in tools below. Use the machine names; the aliases are interchangeable.

| Action a skill requests | Kiro tool | Notes |
| --- | --- | --- |
| Read a file / list a directory | `read` (alias `fs_read`) | Also reads images. |
| Find files by name | `glob` | Respects `.gitignore`. |
| Search file contents | `grep` | Regex, respects `.gitignore`. Use `code` for symbol/LSP search. |
| Create / edit / delete a file | `write` (alias `fs_write`) | Create, overwrite, and targeted string-replace edits. |
| Run a shell command | `shell` (alias `execute_bash`) | Output streams live (CLI ≥ 2.1). |
| Fetch a URL | `web_fetch` | Gated by `toolsSettings.web_fetch.trusted`. |
| Search the web | `web_search` | |
| **Dispatch a subagent** | `subagent` (alias `use_subagent`) | See below. |
| **Create / update todos** | `todo` | Real tool. Older Superpowers text says `TodoWrite`; that means this. |
| **Invoke a skill** | see "Invoking a skill" below | Kiro has no `Skill` tool. |
| AWS API call | `aws` (alias `use_aws`) | Prefer over shelling out to the AWS CLI. |
| Background/async work | `delegate` | Background agents; not a substitute for `subagent`. |

## Invoking a skill

Kiro has **no `Skill` tool**. Its blessed skill-loading mechanisms are:

1. **Automatic activation** — Kiro loads each skill's `name` + `description` at
   startup and expands the full body when your request matches a description.
   This is the default path and matches Claude Code's behavior.
2. **`/skill-name`** — every skill in `.kiro/skills/` (and `~/.kiro/skills/`)
   auto-registers as a slash command that force-loads it (CLI ≥ 2.1).
3. **Reading `SKILL.md` with `read`** — the sanctioned fallback when a skill did
   not auto-activate, or when one skill tells you to use another
   (`superpowers:writing-plans` → `read` the `writing-plans` `SKILL.md`).

`using-superpowers` says never to read skill files manually *instead of* your
platform's mechanism. On Kiro, reading `SKILL.md` **is** one of the platform's
mechanisms — it honors that rule, it does not break it.

**Skills live in two scopes; check both.** A cross-skill reference written as
`superpowers:<skill-name>` resolves to whichever of these exists:

```
.kiro/skills/<skill-name>/SKILL.md      # workspace — wins on a name collision
~/.kiro/skills/<skill-name>/SKILL.md    # global — the catalog installer's default scope
```

Do not conclude a skill is missing because the workspace path is absent; this
catalog installs globally by default, so the `~/.kiro` path is the common case.

Relative links inside a skill
(`./implementer-prompt.md`, `../requesting-code-review/code-reviewer.md`,
`scripts/review-package`) resolve against the skill's own directory — the layout
is preserved from upstream, so follow them as written.

**Custom agents must opt in.** A custom agent only sees skills if its config
lists them:

```json
"resources": [
  "skill://.kiro/skills/*/SKILL.md",
  "skill://~/.kiro/skills/*/SKILL.md"
]
```

## Subagents

`subagent` is a built-in tool and **`kiro_default` already has it** — a default
session can delegate with no configuration. Only a *custom* agent must opt in, by
listing `subagent` in its `tools` array or pulling in `@builtin`; without that it
cannot delegate. Dispatch by describing the task and naming the target agent —
this is **not** `/agent <name>`, which switches your own chat session to that
agent.

- **"Dispatch a `general-purpose` subagent" maps directly.** Kiro ships two
  internal subagents it uses automatically: *context gathering*, and *general
  purpose* — "handles parallelized tasks of any kind using the default agent
  configuration". That default subagent has the same built-in tools as the main
  agent (`read`, `write`, `shell`, `web_search`, `web_fetch`, plus configured MCP
  tools), so it is the right target wherever a skill asks for a general-purpose
  subagent. Name an agent from `.kiro/agents/` instead only when you want that
  agent's narrower tools and permissions — e.g. a read-only reviewer.
- Subagent selection is **description-driven**: the `description` field of an
  agent config decides whether it gets picked. Name *when to delegate* in it.
- Subagents get isolated context and run in parallel; the parent whitelists them
  via `toolsSettings.subagent.availableAgents` and skips per-spawn prompts via
  `trustedAgents`.
- **Hooks do not fire on subagents.** Any safety rule you rely on must live in
  the subagent's own `toolsSettings` (`write.allowedPaths`,
  `shell.deniedCommands`), not in a parent `preToolUse` hook.
- Subagents **do** inherit steering, so the Superpowers bootstrap reaches them.
  That is why `using-superpowers` opens with `<SUBAGENT-STOP>`: if you were
  dispatched to execute one task, ignore that skill and do the task.
- If a subagent needs to be re-driven after a review (the
  `subagent-driven-development` fix loop), dispatch a fresh subagent carrying the
  task brief, the report file, and the findings.

## Skill text that needs a Kiro correction

Skill bodies are vendored verbatim from upstream and predate Kiro support. Two
places where the text is stale for this harness:

- **`executing-plans` says subagents exist on "Claude Code, Codex CLI, Codex App,
  Copilot CLI, and Gemini CLI".** Kiro belongs on that list — `subagent` is a
  built-in tool here, and `kiro_default` has it already. Read that note as
  *including* Kiro: use `superpowers:subagent-driven-development` rather than
  executing the plan inline. Fall back to `executing-plans` only when you are
  running as a custom agent whose `tools` array genuinely omits `subagent`.
- **`using-superpowers`'s "Platform Adaptation" list** points at other harnesses'
  reference files. On Kiro, this file is the one that applies.

## Steering, and where the bootstrap lives

`.kiro/steering/*.md` is Kiro's always-on context. **`kiro-cli` ignores
`inclusion:` frontmatter and loads every steering file in the directory**, which
is what makes `steering/superpowers-bootstrap.md` a reliable session-start
bootstrap. That file is generated — regenerate it with
`scripts/gen-superpowers-bootstrap.sh` after editing `using-superpowers/SKILL.md`
or this file; never hand-edit it.

User instructions (`AGENTS.md`, other steering files, direct requests) outrank
skills, exactly as `using-superpowers` states.

Kiro has no "plan mode". Where a skill says *before entering plan mode, brainstorm
first*, apply it to Kiro's planning surfaces: the `kiro_planner` agent and the
spec workflow (`.kiro/specs/<feature>/requirements.md` → `design.md` →
`tasks.md`). Brainstorm before either. Superpowers' own plan files
(`docs/superpowers/plans/…`, `docs/superpowers/specs/…`) stay where the skills
put them — they are not Kiro specs, and `writing-plans` owns their format.

## Environment detection

Skills that create worktrees or finish branches should detect their environment
with read-only git commands before proceeding:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

- `GIT_DIR != GIT_COMMON` → already in a linked worktree (skip creation)
- `BRANCH` empty → detached HEAD (cannot branch/push/PR)

Kiro exposes git through `shell`; an MCP git server (`@git`) is optional and only
present if configured.

</EXTREMELY_IMPORTANT>
