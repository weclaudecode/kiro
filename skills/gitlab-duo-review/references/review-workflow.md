# How GitLab Duo Code Review (non-agentic) works

This reference covers the reviewer itself — how it is requested, what it
can see, and how custom instructions fit — so the file you author lands in
the right mental model. Authoritative source:
<https://docs.gitlab.com/user/gitlab_duo/code_review/>.

## What it is

GitLab Duo Code Review (non-agentic) is an AI reviewer you add to a merge
request. It posts inline review comments the way a human reviewer would.
It is distinct from the **agentic** Code Review Flow in the Duo Agent
Platform, which is a separate feature with different setup — this skill
targets the non-agentic reviewer and its `mr-review-instructions.yaml`.

## Requirements

- GitLab 18.1 or newer (generally available at 18.1).
- Tier: Premium or Ultimate.
- Add-on: **GitLab Duo Enterprise**.
- To enable **automatic** reviews on a project, Maintainer role or higher.

## Requesting a review

On a merge request, either:

- Assign **GitLab Duo** as a reviewer, or
- Comment the quick action `/assign_reviewer @GitLabDuo`.

Projects can also enable **automatic** review so Duo is requested on new
MRs without a manual step (Maintainer+ to configure). Duo re-reviews when
new changes are pushed, as a human reviewer would on a new revision.

## What the reviewer can see

For the MR under review, Duo is given:

- The MR **title** and **description**.
- The **diffs** and the **filenames** changed.
- The **file contents before the change**, for context.
- Your **custom instructions** whose `fileFilters` match the changed files.

It does not run the code, execute the pipeline, or browse the whole repo;
it reasons over the diff and the surrounding pre-change context plus your
instructions.

## How custom instructions combine

Duo **appends** matching instruction groups to its standard review
criteria — it never replaces them. Instructions from **instance**,
**group**, and **project** levels are merged additively (project is
additive on top of the shared baselines; see `instruction-format.md`).
For each changed file, only the groups whose `fileFilters` match
contribute. When a custom point produces a comment, it is prefixed
`According to custom instructions in '<name>':`, which lets you see which
group fired and tune accordingly.

Because instructions are **guidance, not policy**, the reviewer weighs
them alongside its own criteria and may not surface every point on every
MR. It never blocks the pipeline or the merge.

## Large merge requests

Very large MRs can degrade or fail a review (the diff plus pre-change
context plus instructions can exceed what the model handles well). To keep
reviews reliable:

- **Split large MRs** into smaller, focused ones — better for humans too.
- **Exclude irrelevant files** from the diff (generated code, vendored
  deps, lockfiles) via `.gitlab/duo` scoping and by not committing noise.
- Keep instruction groups **lean** so they do not inflate the context.

If an initial request fails, GitLab may **retry without the pre-change
file contents**; the review still runs but with less context, so its
comments are less specific. Smaller MRs avoid this path.

## Model selection

The model backing Duo Code Review can be configured by a Maintainer or
Owner (where model selection is available for the instance/group). If
reviews are underperforming on a large or specialized codebase, choosing a
different model is one lever — orthogonal to the instructions file, which
you tune independently.

## Where this skill fits

1. Author `.gitlab/duo/mr-review-instructions.yaml` (this skill).
2. Merge it to the target branch so it is active for subsequent MRs.
3. Request Duo on a real MR; read the prefixed comments.
4. Tune globs and phrasing (see `best-practices.md`), repeat.
