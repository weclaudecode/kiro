# Subagent-Driven Development

> Ported from obra/superpowers. Execute a plan by dispatching a **fresh
> subagent per task**, with a two-stage review after each.

**Announce:** "I'm using the subagent-driven-development skill to execute the
plan."

## When to use

You have an implementation plan (`writing-plans.md`) of mostly independent
tasks, and you're staying in the current session. Tightly coupled work or
truly parallel streams call for different handling (see
`dispatching-parallel-agents` in the original, or just run inline via
`executing-plans.md`).

## Why fresh subagents

A new subagent per task gets a clean context — no drift, no interference from
earlier tasks. By crafting precise instructions and context, you keep each
one focused so it succeeds at exactly one task.

## The loop (per task)

1. **Implement.** Dispatch a subagent with the task's files, steps, and
   acceptance criteria. It builds the code test-first
   (`test-driven-development.md`), runs the tests, and self-reviews.
2. **Spec-compliance review.** A reviewer subagent checks the result against
   the plan's requirements — does it do what the task said?
3. **Code-quality review.** A reviewer subagent checks implementation quality
   (clarity, duplication, edge cases, conventions). See
   `requesting-code-review.md`.

If a reviewer finds issues → the implementer fixes them → review again.
**Repeat until approved.** Never accept unresolved issues, and never make an
implementer "retry" without telling it what to change.

## Execution discipline

- **Run continuously.** The user delegated execution of the whole plan —
  don't stop to ask after every task. Update the plan's `- [ ]` checkboxes as
  you go.
- **Match model to task.** Cheap/fast model for mechanical work; a stronger
  model for architectural or ambiguous tasks.
- **Stop and ask** only on a genuine fork the plan didn't anticipate, or a
  failing baseline.

## kiro adaptation

- `Task` → kiro `subagent` tool, invoked as `/agent <name>` or via the
  `subagent` tool's ad-hoc form. Point implementer/reviewer subagents at real
  agent configs in `.kiro/agents/` — they inherit that agent's
  `tools`/`toolsSettings`/`allowedTools` (so a read-only reviewer stays
  read-only). See `docs/agents-guide.md`.
- Up to **four** subagents run concurrently (kiro CLI ≥ 1.23).
- There is no Claude Code "general-purpose" agent type — reference a catalog
  agent (e.g. a reviewer) or describe the subagent's role explicitly.
- A reviewer subagent should receive only the work product (the diff +
  task spec), not your whole session history.

## Never

- Skip either review.
- Force a retry with no change.
- Accept an unresolved issue to "keep moving."
