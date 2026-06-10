# Finishing a Development Branch

> Ported from obra/superpowers. Close out feature work deliberately: verify,
> detect the environment, offer choices, execute, clean up.

**Announce:** "I'm using the finishing-a-development-branch skill."

## Step 1 — Verify tests pass

Run the full suite (`execute_bash`). **If anything fails, stop here** — don't
offer to merge or push broken work. (See
`verification-before-completion.md`.)

## Step 2 — Detect the environment

Are you in a normal checkout or a linked worktree? It changes the options and
the cleanup:

```bash
git rev-parse --git-dir          # under .git/worktrees/… ⇒ worktree
git rev-parse --show-toplevel
```

## Step 3 — Determine the base branch

Find the branch this work split from (usually `main`/`master`):

```bash
git merge-base HEAD origin/main
```

## Step 4 — Present the options

Offer exactly these (a detached HEAD drops option 1):

1. **Merge locally and clean up** — merge into the base, delete the branch,
   remove the worktree.
2. **Push and open a PR** — push the branch, create a pull request.
3. **Keep the branch as-is** — leave everything; no cleanup.
4. **Discard the work** — delete the branch/worktree. **Require the user to
   type a confirmation** before destroying anything.

Let the user choose — don't assume.

## Step 5 — Execute and clean up

- Do the chosen action.
- **Clean up worktrees only on options 1 and 4**, and **only worktrees you
  created** (provenance — don't remove a worktree the user set up).
- Before `git worktree remove`, **`cd` to the main repo root** first, or the
  removal can silently fail.

## kiro adaptations

- This catalog develops on the assigned feature branch and pushes with
  `git push -u origin <branch>`. **Do not open a PR unless the user asks** —
  option 2 means "push the branch," and create the PR only on explicit
  request (use the GitHub tools, not `gh`).
- Never push to a different branch without permission.
- Honor any branch/merge rules in the catalog's steering files.

## Safeguards

- Always verify tests before offering options.
- Typed confirmation before discarding.
- Cleanup is provenance-based and option-gated — never blanket-remove
  worktrees.
