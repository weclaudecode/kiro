<!-- Install to: ~/.kiro/prompts/  OR  <project>/.kiro/prompts/ -->
<!-- Invoke as: @mr-description -->

Generate a GitLab Merge Request description from the current branch's
changes.

Steps:
1. Run `git fetch origin main` then `git log --oneline origin/main..HEAD`
   to enumerate commits.
2. Run `git diff origin/main...HEAD --stat` for the change summary.
3. Read the most-changed files to understand intent.

Output exactly this Markdown structure (no preamble, no closing remarks):

```markdown
## Why
<1–3 sentences: the problem this MR solves. Link the ticket if mentioned in
a commit message.>

## What
<bulleted list of concrete changes, one bullet per logical unit. Group by
file area if there are >5 bullets.>

## How verified
- [ ] Unit tests added/updated and passing
- [ ] `terraform plan` reviewed (link or attach output)
- [ ] Manual verification: <what you did, in 1 line>

## Rollback
<1 sentence: revert the merge commit, then re-run pipeline. If special
steps are needed (data migration, manual cleanup), say so.>

## Notes for reviewers
<optional: anything that needs eyes — naming choices, deferred work, known
gaps. Skip the section if there's nothing.>
```

Don't invent verification you didn't actually do — use checkbox `[ ]` if I
haven't done it yet.
