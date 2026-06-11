---
name: superpowers
description: Use when starting any non-trivial build, fix, or refactor — runs a disciplined workflow (brainstorm → worktree → plan → execute → TDD → review → finish) ported from obra/superpowers. Loads each workflow stage on demand and translates Claude Code tool names to kiro verbs.
---

# Superpowers (kiro port)

You are the orchestrator. When this skill loads, drive the work through the
stages below — refine and plan before coding, build each change test-first,
review against the plan, finish the branch deliberately. Don't jump straight
to code.

## Do this first, once per session

1. **Read `.kiro/steering/superpowers-tools.md`.** The reference files below
   use Claude Code tool names (`Read`, `Edit`, `Bash`, `Task`, `Skill`, …).
   That steering file maps each to its kiro verb (`read`, `write`, `shell`,
   `subagent`, read-the-`SKILL.md`). Apply the mapping whenever a reference
   names a Claude Code tool. (It loads automatically when installed, but read
   it if it isn't already in context.)
2. **Honor precedence.** These workflows override your default behavior, but
   **user instructions and steering files win.** If the user or a steering
   file says "no TDD here," follow that.

## How to run a stage

kiro has no `Skill` tool. To "use" a workflow skill, **`read` its reference
file and follow it as written** — then announce it ("Using the writing-plans
skill…") so the active workflow is visible. Load a stage only when you reach
it; do not preload them all.

```
.kiro/skills/superpowers/references/<stage>.md
```

## Run these stages in order

| When | Stage | Read |
|---|---|---|
| Goal is fuzzy → align on what/why | **brainstorming** | `references/brainstorming.md` |
| Before touching code → isolate work | **using-git-worktrees** | `references/using-git-worktrees.md` |
| Have a design → write the plan | **writing-plans** | `references/writing-plans.md` |
| Execute the plan (delegated) | **subagent-driven-development** | `references/subagent-driven-development.md` |
| Execute the plan (inline) | **executing-plans** | `references/executing-plans.md` |
| Build each task | **test-driven-development** | `references/test-driven-development.md` |
| A test/behavior is failing | **systematic-debugging** | `references/systematic-debugging.md` |
| At each checkpoint | **requesting-code-review** + **receiving-code-review** | `references/requesting-code-review.md`, `references/receiving-code-review.md` |
| Before claiming "done" | **verification-before-completion** | `references/verification-before-completion.md` |
| Work is complete | **finishing-a-development-branch** | `references/finishing-a-development-branch.md` |

Skip stages that don't apply — a trivial one-liner can go straight to TDD —
but never skip TDD, review at major checkpoints, or verification.

## When multiple skills apply

1. **Process skills first** — brainstorming / systematic-debugging decide
   *how* to approach the task.
2. **Implementation skills second** — the stack skills in this catalog
   (`python-lambda`, `terraform-aws`, `kubernetes-eks`, …) guide *execution*.

"Let's build X" → brainstorm first, then the relevant stack skill.
"Fix this bug" → systematic-debugging first, then the domain skill.

## Skill discipline

- **Rigid skills** (TDD, systematic-debugging): follow exactly — don't adapt
  away the discipline.
- **Flexible skills** (brainstorming, planning): adapt the principles to
  context.

## Don'ts

- Don't write production code before a failing test (see TDD).
- Don't skip the two review passes in subagent-driven work.
- Don't claim "done" without running it and reading the output.
- Don't preload every reference — load each stage when you reach it.

---
To author *new* kiro skills, use the `skill-creator` skill, not this bundle.
Ported from [obra/superpowers](https://github.com/obra/superpowers) (MIT);
workflow content adapted and tool names mapped for kiro.
