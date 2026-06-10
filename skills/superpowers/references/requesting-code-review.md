# Requesting Code Review

> Ported from obra/superpowers. Dispatch a focused reviewer subagent at
> natural checkpoints — review early, review often.

**Announce:** "I'm using the requesting-code-review skill."

## When to review

**Required:**
- After each task in subagent-driven development.
- After finishing a major feature.
- Before merging to the main branch.

**Recommended:**
- When you're stuck and want a fresh perspective.
- Before a refactor.
- After a complex bug fix.

## Why a subagent

Dispatch a dedicated reviewer with **focused context** — the work product,
not your whole session history. That keeps the reviewer concentrated on the
diff itself and avoids it rationalizing the choices it watched you make.

## Process

1. **Get the commit range.** Identify the base and the current HEAD:
   ```bash
   git merge-base HEAD <base-branch>   # base SHA
   git rev-parse HEAD                  # head SHA
   ```
2. **Dispatch the reviewer.** Give it:
   - a description of the work completed,
   - the relevant requirements / plan tasks,
   - the base and head SHAs (so it reviews `git diff base...head`).
3. **Address feedback systematically:**
   - **Critical** → fix immediately.
   - **Important** → fix before proceeding.
   - **Minor** → note for later.
   - Push back, with reasoning, when a comment is wrong — review is a
     dialogue, not dictation.

## kiro adaptation

- `Task` (general-purpose reviewer) → kiro `subagent` / `/agent <name>`.
  This catalog ships reviewer agents — e.g. `mr-reviewer`,
  `security-auditor`, `terraform-reviewer` — point the subagent at the right
  one. They're read-only by config, which is exactly what a reviewer wants.
- Feed the reviewer the diff via `git diff base...head` (it can run this
  itself with `@git` / `execute_bash`), plus the plan task it's checking.
- For the two-stage review in subagent-driven work, run **spec-compliance**
  and **code-quality** as two separate reviewer passes.

See also `receiving-code-review.md` for how to act on what comes back.
