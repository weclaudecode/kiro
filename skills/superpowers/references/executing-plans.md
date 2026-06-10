# Executing Plans (inline)

> Ported from obra/superpowers. The alternative to subagent-driven execution:
> work the plan yourself, in the current session, with review checkpoints.

**Announce:** "I'm using the executing-plans skill to implement the plan."

## When to use

You have a plan from `writing-plans.md` and either the tasks are tightly
coupled, the plan is small, or you simply want to keep everything in one
context rather than dispatching subagents. Otherwise prefer
`subagent-driven-development.md`.

## The loop

Work the plan **task by task, step by step, in order**:

1. Read the next unchecked `- [ ]` step.
2. Do exactly that step — no more (the plan already decomposed the work).
3. For implementation steps, follow `test-driven-development.md`: failing
   test → watch it fail → minimal code → watch it pass.
4. Update the checkbox to `- [x]` with `fs_write` as each step completes.
5. Commit at each task's commit step with the message the plan specifies.

## Review checkpoints

Don't wait until the end. Request a code review (`requesting-code-review.md`)
at natural boundaries — after each major task or feature — so issues don't
accumulate. Address findings before moving on.

## Discipline

- **Follow the plan; don't improvise.** If reality diverges from the plan
  (a step is wrong, a file moved, a test is infeasible as written), **stop and
  fix the plan first**, then continue — don't silently freelance.
- Keep the working tree green between tasks.
- If you hit a real fork the plan didn't cover, surface it to the user.

## kiro note

Run every test and command with `execute_bash` and actually read the output.
The plan's checkboxes are your only task tracker (no `TodoWrite` in kiro).

## When finished

Hand off to `verification-before-completion.md`, then
`finishing-a-development-branch.md`.
