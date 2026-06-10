# Verification Before Completion

> Ported from obra/superpowers. Don't claim "done" on belief — claim it on
> evidence.

**Announce:** "I'm using the verification-before-completion skill."

## The rule

```
NO "DONE" WITHOUT EVIDENCE
```

Before you tell the user a task is complete, you must have *watched* it work.
"It should work" is not verification.

## Checklist

- [ ] **Tests run and pass** — you executed the suite (`execute_bash`) and
      read the output, this session, on the current code. Not "they passed
      earlier."
- [ ] **Output is pristine** — no errors, no new warnings, no skipped tests
      you didn't account for.
- [ ] **The actual requirement is met** — re-read the original ask / plan and
      confirm each requirement is satisfied, not just the happy path.
- [ ] **You ran the real thing** — for a CLI/app/endpoint, you invoked it and
      observed correct behavior, not just unit tests.
- [ ] **Edge cases and error paths** covered, not just the golden path.
- [ ] **No debris** — no leftover debug prints, commented-out code, scratch
      files, or `TODO`s you introduced.
- [ ] **Working tree is intentional** — `git status` / `git diff` shows only
      what you meant to change.

## Honesty

If something is *not* verified, say so plainly: which step you skipped, what
failed, what's still unknown. A truthful "tests pass but I couldn't exercise
the Lambda end-to-end" beats a confident false "done."

## Red flags

- "Should work" / "looks right" / "I think that's it."
- Marking complete without running anything this session.
- Reporting success while tests are red or output has warnings.
- Inferring a result instead of observing it.

## kiro note

This catalog has a `verify` workflow for exercising a change in the real app
— use it when unit tests alone don't prove the behavior. Reference findings
as `path:line`.
