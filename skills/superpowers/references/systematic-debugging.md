# Systematic Debugging

> Ported from obra/superpowers. A **rigid** skill: find the root cause before
> you touch anything.

**Announce:** "I'm using the systematic-debugging skill."

## The rule

```
NO FIXES WITHOUT ROOT-CAUSE INVESTIGATION FIRST
```

Random patches mask the problem instead of solving it. Work the four phases
in order.

## Phase 1 — Root-cause investigation

- Read the **full** error message and stack trace — don't skim.
- Reproduce it reliably. If you can't reproduce it, you can't fix it.
- Check what changed recently (`git log`, `git diff`, recent deploys).
- Gather evidence across the stack (logs, inputs, state) with `fs_read` /
  `execute_bash`.
- Trace the data flow **backward** from the symptom to its origin.

## Phase 2 — Pattern analysis

- Find comparable code that *works*. Read the reference implementation fully.
- Identify every difference between the working and broken paths.
- Understand the dependencies involved before forming a theory.

## Phase 3 — Hypothesis and test

- State a specific, falsifiable hypothesis about the root cause.
- Test it with the **smallest possible change** (a probe, a log line, a unit
  test) — not a speculative fix.
- Let evidence revise the hypothesis. Don't marry your first guess.

## Phase 4 — Implement the fix

- **Write a failing test that reproduces the bug first** (see
  `test-driven-development.md`), then make it pass.
- Make **one** targeted fix. Verify it. Confirm no regressions.
- **If three fixes in a row each expose a new problem in a different area,
  stop** — the design pattern itself is probably wrong. Step back and question
  the architecture rather than patching further.

## Red flags

- Proposing a fix before understanding the cause.
- Changing several things at once.
- "Quick fix now, investigate later."
- Proceeding without a reliable reproduction.

## kiro note

Pull evidence yourself with read-only `execute_bash` and `@git` — quote the
decisive log line / stack frame in your explanation so the conclusion is
traceable.
