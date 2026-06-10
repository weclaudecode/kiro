# Using Git Worktrees

> Ported from obra/superpowers. Create an isolated workspace on a new branch
> before starting implementation, so work-in-progress never collides with the
> main checkout.

**Announce:** "I'm using the using-git-worktrees skill to set up an isolated
workspace."

## Rule

**Detect existing isolation first. Then use native tools. Then fall back to
git.** Never fight the environment's built-in isolation.

## Step 0 — Are you already isolated?

Before anything, check whether the current directory is already a linked
worktree or a fresh clone:

```bash
git rev-parse --git-dir          # ".git" → main checkout; a path under
                                 # .git/worktrees/… → already a worktree
git rev-parse --show-toplevel
```

If you're already in an isolated workspace (a dedicated worktree or a
throwaway clone — common in CI and remote-exec environments), **skip
creation** and just make/switch to your feature branch.

> In this catalog's remote-execution sessions you are typically already in an
> isolated clone on a feature branch. In that case, do not create a nested
> worktree — just confirm the branch and proceed.

## Step 1 — Create the worktree (if needed)

Pick the directory in this priority order:

1. An explicit path the user gave you.
2. An existing project-local worktree dir (e.g. `.worktrees/`).
3. Default: `.worktrees/<branch-name>/`.

```bash
git worktree add .worktrees/<feature> -b <feature>
```

**Before creating a project-local worktree dir, verify it is git-ignored**
(`git check-ignore .worktrees` or add it to `.gitignore`). An un-ignored
worktree directory pollutes the parent repo's status.

## Step 2 — Set up the workspace

`cd` into the worktree and install dependencies the way the project expects
(`uv sync` / `pip install -e .`, `npm ci`, `terraform init`, etc.).

## Step 3 — Verify a clean baseline

Run the test suite once before writing anything. If the baseline is already
red, **stop and tell the user** — don't build on a broken base without their
say-so.

## kiro adaptations

- Use `execute_bash` for all git/worktree commands; `@git` for status/log/diff.
- Branch naming follows the project's convention (this catalog develops on
  the assigned `claude/...` feature branch — don't create divergent branches
  without permission).

## Common mistakes

- Using `git worktree add` when you're already in an isolated workspace.
- Forgetting to git-ignore a project-local worktree directory.
- Proceeding past a failing baseline without explicit consent.

## Cleanup

Worktree teardown is handled by `finishing-a-development-branch.md` — only
remove worktrees that *you* created.
