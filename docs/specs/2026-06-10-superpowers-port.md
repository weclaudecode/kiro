# Superpowers Port — Design

**Date:** 2026-06-10
**Status:** Implemented
**Repo:** `weclaudecode/kiro` (this repo)
**Upstream:** [obra/superpowers](https://github.com/obra/superpowers) (MIT)
**Tracking:** obra/superpowers issue #503 ("Kiro CLI support"), PR #618

## Purpose

Port the **core software-development workflow** from obra/superpowers into
this kiro catalog, and supply the platform adaptation that lets a kiro agent
run skill text written for Claude Code.

Superpowers is a methodology built from composable skills: brainstorm →
isolate in a git worktree → write a detailed plan → execute it (subagent-driven
or inline) → drive each change test-first → review against the plan → finish
the branch deliberately, with systematic-debugging and
verification-before-completion as cross-cutting discipline.

## What issue #503 / PR #618 told us

Upstream #503 asks for first-class Kiro support; PR #618 explores a Kiro IDE
"Power" (`POWER.md` + a global `steering/` bootstrap that reads skills off
disk rather than copying them). Two takeaways we adopted:

1. **Don't copy 14 skill dirs into a rigid layout.** Keep the workflow as
   on-demand reference files the agent reads when relevant.
2. **Kiro has no `Skill`/`discloseContext` parity for arbitrary files** — a
   skill is loaded by reading its `SKILL.md`. So skills must reference each
   other by path, and Claude Code tool names must be translated.

We diverge from #618 in one way: this is the **kiro CLI catalog**, not the IDE
Power model, so the port installs via the existing `scripts/install.sh`
manifest flow (consistent with every other artifact here), not a `POWER.md`.

## What was added

- `skills/superpowers/SKILL.md` — router/meta skill (port of
  `using-superpowers`): when to use the workflow, how to load a skill in kiro
  (read the reference file), skill priority, attribution.
- `skills/superpowers/references/*.md` — the ported core workflows:
  brainstorming, using-git-worktrees, writing-plans, executing-plans,
  subagent-driven-development, test-driven-development, systematic-debugging,
  requesting-code-review, receiving-code-review,
  finishing-a-development-branch, verification-before-completion.
- `steering/superpowers-tools.md` — **the platform adaptation**: an
  `inclusion: always` steering block with the Claude Code → kiro **tool
  mapping table** (`Read`→`fs_read`, `Edit`/`Write`→`fs_write`,
  `Bash`→`execute_bash`, `Task`→`subagent`, `Skill`→read the
  `SKILL.md`, `TodoWrite`→plan checkboxes, `WebFetch`→`web`, …) plus the
  cross-skill reference convention and what does *not* translate.
- Registered both in `scripts/manifest.txt`; indexed in `skills/README.md`
  and the two catalog READMEs.

## Design decisions

- **Tool mapping lives in steering, not in each skill.** Per the request, the
  translation table is one always-on steering block so the LLM converts
  Claude Code commands to kiro verbs wherever a ported skill uses them —
  rather than rewriting every tool reference inline (which would drift from
  upstream and bloat each file).
- **`writing-skills` is not ported.** The catalog already ships
  `skill-creator` for authoring kiro skills; the meta SKILL.md points there.
- **`dispatching-parallel-agents` folded into subagent-driven-development**,
  mapped onto kiro's `subagent` tool (≤ 4 concurrent) and real `.kiro/agents/`
  configs so reviewers stay read-only by inheriting that agent's gating.
- **Catalog branch/PR norms win.** `finishing-a-development-branch` is adapted
  so "push" never auto-opens a PR; PRs are created only on explicit request.

## Non-goals

- No `POWER.md` / Kiro IDE Power packaging (CLI-catalog port only).
- No verbatim copy of upstream skill bodies — content is adapted for kiro
  tooling and idioms, with attribution retained.
- No auto-install: opt-in per artifact like everything else in the catalog.
