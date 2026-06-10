---
name: superpowers
description: Use when starting development work of any size — a disciplined software-development workflow (brainstorm → plan → worktree → TDD → review → finish) ported from obra/superpowers for kiro. Establishes how to find and apply the workflow skills, and translates Claude Code tool names to kiro equivalents.
---

# Superpowers (kiro port)

## Overview

Superpowers is a complete software-development methodology for coding agents,
built from a set of composable workflow skills. It keeps you from jumping
straight to code: you refine the idea, plan it, isolate the work, drive it
test-first, review against the plan, and finish the branch deliberately.

This is a port of [obra/superpowers](https://github.com/obra/superpowers)
(MIT) adapted for the **kiro CLI**. The original uses Claude Code tool names;
the `superpowers-tools` steering file holds the translation table. Read it
once at the start of a session, then map every `Read`/`Edit`/`Bash`/`Task`/
`Skill` reference in these skills to its kiro verb (`fs_read`/`fs_write`/
`execute_bash`/`subagent`/read-the-`SKILL.md`).

## When to Use

Reach for the superpowers workflow whenever you are building, fixing, or
changing real software — a feature, a bug fix, a refactor. The bigger or
fuzzier the task, the more of the workflow you use. Trivial one-liners can
skip straight to TDD.

When NOT to use: throwaway prototypes, generated code, or pure config edits —
though even then the TDD and verification skills usually still apply.

## How to use these skills in kiro

kiro has no `Skill` tool. Each workflow lives as a reference file in this
bundle. To "invoke a skill," **read the file with `fs_read`** and follow it
directly:

```
.kiro/skills/superpowers/references/<skill-name>.md
```

Announce which skill you are using ("I'm using the writing-plans skill…") so
the active workflow is visible. Process skills override default behavior, but
**user instructions and steering files always take precedence** — if a
steering file or the user says "no TDD here," follow that.

## The core workflow

Run these in order for a typical feature. Each links to its reference file.

| Stage | Skill | Read |
|---|---|---|
| 1. Refine the idea | **brainstorming** | `references/brainstorming.md` |
| 2. Isolate the work | **using-git-worktrees** | `references/using-git-worktrees.md` |
| 3. Plan it | **writing-plans** | `references/writing-plans.md` |
| 4a. Execute (delegated) | **subagent-driven-development** | `references/subagent-driven-development.md` |
| 4b. Execute (inline) | **executing-plans** | `references/executing-plans.md` |
| 5. Build each task | **test-driven-development** | `references/test-driven-development.md` |
| (when stuck) | **systematic-debugging** | `references/systematic-debugging.md` |
| 6. Review | **requesting-code-review** / **receiving-code-review** | `references/requesting-code-review.md`, `references/receiving-code-review.md` |
| 7. Finish | **finishing-a-development-branch** | `references/finishing-a-development-branch.md` |
| Before "done" | **verification-before-completion** | `references/verification-before-completion.md` |

## Skill priority

When several skills could apply:

1. **Process skills first** (brainstorming, systematic-debugging) — they
   decide *how* to approach the task.
2. **Implementation skills second** (the stack skills in this catalog:
   `python-lambda`, `terraform-aws`, `kubernetes-eks`, …) — they guide
   *execution*.

"Let's build X" → brainstorm first, then the relevant stack skill.
"Fix this bug" → systematic-debugging first, then the domain skill.

## Skill types

- **Rigid** (TDD, systematic-debugging): follow exactly. Don't adapt away the
  discipline.
- **Flexible** (brainstorming, planning): adapt the principles to context.

## Authoring new skills

This catalog already ships `skill-creator` for scaffolding and tuning kiro
skills — use that rather than the original's `writing-skills` skill.

## Attribution

Ported from obra/superpowers (MIT License). Workflow content adapted; tool
names and install model changed for kiro. See `references/` for per-skill
ports and `steering/superpowers-tools.md` for the tool mapping.
