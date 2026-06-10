# Test-Driven Development (TDD)

> Ported from obra/superpowers. Write the test first, watch it fail, write the
> minimal code to pass. A **rigid** skill — follow it exactly.

**Announce:** "I'm using the test-driven-development skill."

**Core principle:** if you didn't watch the test fail, you don't know that it
tests the right thing. *Violating the letter of the rules is violating the
spirit of the rules.*

## When to use

**Always:** new features, bug fixes, refactors, behavior changes.

**Exceptions (ask the user first):** throwaway prototypes, generated code,
config files.

Thinking "skip TDD just this once"? Stop. That's rationalization.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote code before the test? **Delete it. Start over.** No exceptions: don't
keep it "as reference," don't "adapt" it, don't look at it. Implement fresh
from the tests.

## Red–Green–Refactor

### RED — write a failing test

One minimal test of one real behavior, with a clear name and real code (no
mocks unless unavoidable). Test *behavior*, not the mock.

### Verify RED — watch it fail (MANDATORY)

Run the test (`execute_bash`). Confirm it **fails** (not errors), and fails
because the feature is missing — not because of a typo.
- Passes already? You're testing existing behavior. Fix the test.
- Errors? Fix the error and re-run until it fails cleanly.

### GREEN — minimal code

Write the simplest code that passes. No extra options, no speculative
features (YAGNI), no refactoring of unrelated code.

### Verify GREEN — watch it pass (MANDATORY)

Run the test again. Confirm it passes, **other tests still pass**, and output
is pristine (no warnings/errors).
- Test fails? Fix the *code*, not the test.
- Other tests fail? Fix them now.

### REFACTOR

Only once green: remove duplication, improve names, extract helpers. Keep
tests green. Add no behavior.

### Repeat

Next failing test for the next behavior.

## Good tests

| Quality | Good | Bad |
|---|---|---|
| Minimal | one thing — "and" in the name means split it | `test('validates email and domain and whitespace')` |
| Clear | name describes the behavior | `test('test1')` |
| Intent | demonstrates the desired API | obscures what the code should do |

## Common rationalizations (all mean: start over with TDD)

- "Too simple to test" — simple code breaks; the test takes 30s.
- "I'll test after" — tests written after pass immediately and prove nothing.
- "Already manually tested" — ad-hoc ≠ systematic; no record, can't re-run.
- "Deleting X hours is wasteful" — sunk cost; unverified code is debt.
- "Keep as reference" — you'll adapt it; that's testing-after. Delete.
- "TDD is dogmatic, I'm pragmatic" — TDD *is* pragmatic; shortcuts = debugging
  in prod.

## Red flags — STOP

Code before test · test passes immediately · can't explain why it failed ·
tests added "later" · "this is different because…". All mean: delete, restart
with TDD.

## When stuck

| Problem | Fix |
|---|---|
| Don't know how to test | Write the wished-for API / the assertion first. Ask the user. |
| Test too complicated | Design too complicated — simplify the interface. |
| Must mock everything | Code too coupled — use dependency injection. |

## Debugging integration

Bug found? Write a failing test that reproduces it, then run the cycle. The
test proves the fix and prevents regression. Never fix a bug without a test.

## kiro note

Run tests with `execute_bash` (e.g. `uv run pytest path::test`,
`npm test path`). The two "verify" steps are non-negotiable: actually run the
command and read the output — don't assume.
