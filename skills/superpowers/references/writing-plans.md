# Writing Plans

> Ported from obra/superpowers. Produce a thorough implementation plan
> *before* writing code: exact files, real test/impl code, validation, and a
> commit strategy, broken into 2–5 minute steps.

**Announce:** "I'm using the writing-plans skill to create the implementation
plan."

Assume the implementer is competent but unfamiliar with your tools and
domain. Spell everything out. Follow DRY, YAGNI, and TDD, with a commit at
the end of each task.

**Plan location:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
(a user-specified directory wins over this default). Write it with `fs_write`.

## Scope validation

If the spec spans multiple independent systems, split it into **one plan per
system** — each plan should produce independently working, testable software.
Recommend the split before writing.

## File organization

Before sequencing tasks, list the files you'll create or modify and each
one's single responsibility:

- One clear purpose per file; clean interfaces.
- Co-locate interdependent files; organize by function, not by technical
  layer.
- Respect existing codebase conventions.

This mapping drives task decomposition into self-contained, independent
changes.

## Task granularity

One action per step (2–5 minutes each):

1. Write the failing test.
2. Run it; confirm it fails for the right reason.
3. Write the minimal implementation.
4. Run it; confirm it passes.
5. Commit.

## Plan header

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use
> subagent-driven-development (recommended) or executing-plans to implement
> this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [one sentence — what this builds]
**Architecture:** [2–3 sentences — the approach]
**Tech Stack:** [key technologies/libraries]

---
```

## Task format

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test:   `tests/exact/path/to/test_file.py`

- [ ] **Step 1: Write the failing test**
[complete test code]

- [ ] **Step 2: Run the test, verify it fails**
Run: [exact command]   Expected: [specific failure]

- [ ] **Step 3: Write minimal implementation**
[complete implementation code]

- [ ] **Step 4: Run the test, verify it passes**
Run: [exact command]   Expected: PASS

- [ ] **Step 5: Commit**
[exact git commands + message]
````

## Prohibited in plans

- Placeholders / "TODO later" markers.
- Vague directives with no implementation detail.
- Tests mentioned without actual code.
- Implicit cross-task references.
- Undefined types or method signatures.

## Quality checklist before handoff

1. **Coverage:** every requirement maps to ≥1 task.
2. **No placeholders:** every prohibited pattern removed.
3. **Type consistency:** names/signatures match across related tasks.

## Execution options (present at the end)

1. **Subagent-driven (recommended)** — fresh agent per task, review between
   tasks. See `subagent-driven-development.md`.
2. **Inline** — execute in the current session with review checkpoints. See
   `executing-plans.md`.

## kiro note

`TodoWrite` has no kiro equivalent — the plan file's `- [ ]` checkboxes *are*
the task tracker. Update them with `fs_write` as steps complete.
