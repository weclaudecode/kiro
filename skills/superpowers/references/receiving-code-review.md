# Receiving Code Review

> Ported from obra/superpowers. How to act on review feedback — yours to
> triage, not to obey blindly.

**Announce:** "I'm using the receiving-code-review skill."

## Mindset

Review feedback is data, not orders. Your job is to reach correct, working
code — sometimes that means doing what the reviewer says, sometimes it means
explaining why they're wrong. Don't get defensive, and don't cave reflexively.

## Triage every comment

| Severity | Action |
|---|---|
| **Critical** (bug, security, data loss, breaks the spec) | Fix immediately, before anything else. |
| **Important** (correctness risk, missing edge case, bad pattern) | Fix before you proceed past this checkpoint. |
| **Minor** (style, naming, nits) | Fix if cheap; otherwise note and batch. |
| **Wrong** (reviewer misunderstood) | Reply with the reasoning and evidence; don't change the code just to satisfy it. |

## Discipline

- **Fix the cause, not the symptom.** If a comment points at a deeper design
  issue, address the design — don't paper over the specific line.
- **Re-run the tests after every fix.** A review fix is still a code change;
  it gets the same `test-driven-development.md` rigor. Add a failing test
  first when the comment describes a real bug.
- **Don't introduce new behavior** under cover of "addressing review." Keep
  the change scoped to the feedback.
- **Close the loop.** For each comment: fixed (and how), or declined (and
  why). Nothing left dangling.

## In subagent-driven development

The cycle is: reviewer finds issues → implementer fixes → review again →
**repeat until approved**. Don't accept an unresolved issue to keep moving,
and don't retry without actually changing something.

## kiro note

When the review came from a reviewer subagent, apply fixes with
`fs_write`, re-run tests with `execute_bash`, then dispatch the reviewer
again on the new diff. On a real PR, reply to review threads via the GitHub
tools rather than silently force-pushing over them.
