# Superpowers Port — Design

**Date:** 2026-06-10 (rev. 2026-08-04)
**Status:** Implemented
**Repo:** `weclaudecode/kiro` (this repo)
**Upstream:** [obra/superpowers](https://github.com/obra/superpowers) v6.2.0 (MIT), commit `44c9b2d`
**Tracking:** obra/superpowers issue #503 ("Kiro CLI support"), PR #618

## Purpose

Run the obra/superpowers methodology on Kiro **with the same behavior it has on
Claude Code**: the same skills, triggering the same way, in the same order.

Superpowers is a methodology built from composable skills: brainstorm →
isolate in a git worktree → write a detailed plan → execute it (subagent-driven
or inline) → drive each change test-first → review against the plan → finish
the branch deliberately, with systematic-debugging and
verification-before-completion as cross-cutting discipline.

## The two rules that shape this port

Upstream's `docs/porting-to-a-new-harness.md` is explicit, and the 2026-08-04
revision brings this port into line with both rules:

1. **Skills name actions, not tools — never edit skill bodies.** A port adds a
   tool mapping and a bootstrap; it does not rewrite `SKILL.md`. Upstream skill
   text is already harness-neutral (no `Task`, no `TodoWrite`, no
   `${CLAUDE_PLUGIN_ROOT}`), so it runs on Kiro unmodified.
2. **The bootstrap is the entire integration.** `using-superpowers` must be in
   context at the start of every session with no per-session opt-in. Without it
   the skill files are inert — present on disk, never invoked.

## Integration shape: C (instructions-file)

Kiro has no session-start hook that can inject context — `agentSpawn` stdout is
*not* added to the conversation (only `userPromptSubmit` stdout is, and that
fires per turn, not per session). Kiro's guaranteed session-start surface is
steering: **`kiro-cli` ignores `inclusion:` frontmatter and loads every file in
`.kiro/steering/`**. That makes steering the bootstrap carrier — upstream's
Shape C, the same shape Gemini uses.

The bootstrap is *generated*, not hand-written, so it can't drift from its
sources:

```
skills/using-superpowers/SKILL.md            ─┐
skills/using-superpowers/references/kiro-tools.md ─┴─► scripts/gen-superpowers-bootstrap.sh
                                                        └─► steering/superpowers-bootstrap.md
```

`scripts/gen-superpowers-bootstrap.sh --check` fails if the committed file is
stale. Steering file references (`#[[file:...]]`) are deliberately **not** used:
upstream warns that include syntax may resolve to "the model may choose to read
this" rather than guaranteed inlining, and that is exactly the guarantee the
bootstrap cannot trade away.

## What is installed

- `skills/<14 upstream skills>/` — vendored **verbatim**, including every
  bundled prompt template (`implementer-prompt.md`, `code-reviewer.md`, …),
  helper script (`scripts/review-package`, `scripts/sdd-workspace`,
  `scripts/task-brief`, `find-polluter.sh`, the brainstorming visual companion)
  and technique file. Upstream's sibling layout is preserved, so relative links
  (`../requesting-code-review/code-reviewer.md`) resolve as written. Only the
  eval fixtures (`test-pressure-*.md`, `CREATION-LOG.md`) are dropped.
- `skills/using-superpowers/references/kiro-tools.md` — the action → Kiro tool
  mapping (the port's only real content), plus the subagent, skill-invocation
  and steering notes.
- `steering/superpowers-bootstrap.md` — generated bootstrap, `inclusion: always`.
- `skills/using-superpowers/LICENSE` — upstream MIT license, retained.

The single permitted edit to an upstream `SKILL.md` is the one the porting guide
sanctions: one line added to `using-superpowers`'s "Platform Adaptation" pointer
list (`- Kiro: references/kiro-tools.md`).

## Kiro facts the mapping depends on

| Fact | Consequence |
|---|---|
| No `Skill` tool; skills auto-activate on description match, register as `/skill-name` (CLI ≥ 2.1), and can be `read` directly | "Invoke a skill" has three sanctioned paths; reading `SKILL.md` honors the "don't bypass the mechanism" rule rather than breaking it |
| `todo` is a real built-in tool | Task tracking maps to a tool, not to plan-file checkboxes |
| `grep`, `glob`, `code`, `web_search`, `web_fetch` are distinct built-ins | Search and web actions map 1:1 |
| The default subagent has the same built-in tools as the main agent | `general-purpose` maps to the default subagent, not to a named catalog agent |
| Subagents inherit steering; hooks do **not** fire on subagents | `<SUBAGENT-STOP>` in the bootstrap does the work a hook can't; subagent safety lives in `toolsSettings` |
| Custom agents only see skills listed in `resources` | `kiro_default` gets superpowers automatically; custom agents must add `skill://.kiro/skills/*/SKILL.md` |

## Known gaps

- **Acceptance test not run here.** Upstream's definition of done requires a
  live session where "Let's make a react todo list" triggers `brainstorming`
  before any code. That needs an authenticated `kiro-cli`, which this
  environment does not have. Run it before treating the port as verified.
- **Issue #6680** — `skill://` sometimes loads full bodies at startup instead of
  frontmatter only. With 14 skills that is real context cost until it is fixed;
  it is a Kiro bug, not a port decision.
- **Headless mode** — steering loads the same way under
  `kiro-cli chat --no-interactive`, so the bootstrap applies there too, but the
  subagent-heavy skills assume an interactive partner.

## Non-goals

- No `POWER.md` / Kiro IDE Power packaging (CLI-catalog port only).
- No auto-install: opt-in per artifact like everything else in the catalog.
- Upstream distribution (a PR against obra/superpowers adding a Kiro shape) is
  out of scope for this repo.

## Superseded decisions (pre-2026-08-04)

The first cut adapted and condensed the workflows into
`skills/superpowers/references/*.md` behind one router skill, with the mapping
in `steering/superpowers-tools.md`. That diverged from Claude Code behavior in
three ways that mattered, and all three are fixed above: condensed skill bodies
lost the behavioral pressure upstream tunes for; sub-skills had no frontmatter,
so nothing auto-triggered; and there was no bootstrap, so the router itself only
loaded if the user asked for it by name.
