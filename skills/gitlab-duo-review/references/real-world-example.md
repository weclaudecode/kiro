# Learning from a production instructions file

GitLab maintains its own `mr-review-instructions.yaml` for the
`gitlab-org/gitlab` monorepo. It is the largest public, battle-tested
example and a better teacher than any synthetic sample. Read it:

<https://gitlab.com/gitlab-org/gitlab/-/blob/master/.gitlab/duo/mr-review-instructions.yaml>

This reference distills the transferable techniques from it — patterns you
can apply to any project, not the GitLab-specific content. (Its groups are
Ruby/Rails/GitLab-specific: *General Standards*, *Ruby Code Quality*,
*Database Migrations*, *Cells Architecture*, *Sidekiq Worker
Compatibility*, *Authentication & Authorization Security*, *Authentication
Review Heuristics*, *Authentication Test Quality*, *Documentation*,
*API documentation*, *RSpec*, *E2E Testing*, *Feature Flag Removal
Safety*, *Internal Analytics*, *ViewComponent Best Practices*, and more.)

## 1. Group by *concern and process*, not only by language

The most valuable groups aren't "Ruby files" — they are the ones scoped to
a **workflow or architectural rule** the team keeps getting wrong:

- **Database Migrations** (`db/migrate/**/*.rb`, `db/docs/**/*.yml`) —
  reversibility, batching, index-on-FK, table-size limits, column ordering.
- **Feature Flag Removal Safety** (`config/feature_flags/**/*.yml` +
  `**/*.rb` + `**/*.vue` + `spec/**/*.rb`) — catches half-removed flags
  across backend, frontend, and specs.
- **Internal Analytics / Events** (`config/events/**/*.yml`,
  `config/metrics/**/*.yml`) — event-definition correctness.
- **Localization** (`locale/gitlab.pot`), **Schema Migrations**,
  **ViewComponent**, **Experiments**.

Takeaway: after you cover each language, ask *"what process do we have a
runbook or a wiki page for, that reviewers police by hand?"* — migrations,
feature flags, public API changes, i18n, telemetry, changelog rules — and
give each its own group scoped to the files that trigger it.

## 2. The Ask / Remind / Suggest pattern

Instead of only asserting checks, GitLab's file tells the reviewer to pose
**questions to the author** and surface **reminders with doc links**:

```
- Ask: "What is the current size of this table, and what is the projected
   size after adding this column? Tables cannot exceed 50 GB ..."
- Remind: "Redundant and orphaned indexes increase storage overhead ...
   See: https://docs.gitlab.com/development/database/adding_database_indexes/"
- Suggest: "For investigating index usage you can start by gathering all
   the metadata available for the index ..."
```

This works *with* the guidance-not-policy nature of the reviewer: a
question the author must answer, or a doc link, is more actionable than a
flat "must." Use `Ask:` when the answer requires human context the model
can't see, `Remind:`/`Suggest:` to attach the canonical doc. It also names
the escape hatch honestly — GitLab's flag group says *"the agent cannot
determine ZDU safety from code structure alone"* and routes it to human
review rather than pretending the hint enforces it.

## 3. Condition guidance on what the diff does

Points are scoped *within* a group by the change they apply to:

```
For migrations that drop or replace an index:
  - Remind: "Before removing an index, verify queries can use other ..."
For new tables created in the current merge request:
  - Check if columns are ordered optimally for space efficiency ...
```

`For <situation>: …` / `When this MR touches <X>, check <Y>` keeps a big
group focused — the reviewer only weighs the sub-points relevant to the
actual diff.

## 4. Split one domain into source / heuristics / tests

Authentication appears as **three** groups, each with its own file scope:

- **Authentication & Authorization Security** — the source files (models,
  services, controllers, policies).
- **Authentication Review Heuristics** — the policy/ability files, with
  reasoning-style guidance for the reviewer.
- **Authentication Test Quality** — the `_spec.rb` files, checking the
  *tests* are meaningful.

Splitting by concern lets each group carry tightly-relevant points and
scope to exactly the right files, instead of one sprawling group.

## 5. Precise fileFilters — down to single files and filename wildcards

The auth group lists **specific files**, not just directory globs:

```
- "app/controllers/sessions_controller.rb"
- "app/controllers/concerns/authenticates_with_two_factor*.rb"
- "app/controllers/concerns/enforces_*authentication*.rb"
- "config/initializers/doorkeeper*.rb"
```

Wildcards work **inside** filenames (`*two_factor*`), and you can pin one
exact file when only it matters. For a mirrored monorepo, list both trees
(`app/...` **and** `ee/app/...`). Precise filters mean the group's
guidance only reaches the code it was written for.

## 6. A header block with references

The file opens with a comment header linking the org's own guideline docs
(Code Review Guidelines, Database Review, Documentation Styleguide, design
system, etc.) and a one-line note on how the file works. This documents
provenance for the next maintainer and gives each group a canonical source
to cite. Reproduce this pattern (see `assets/mr-review-instructions.yaml`).

## 7. Directive verbs are fine; absolute mandates are not

GitLab's points use **Ensure / Verify / Check / Flag / Ask / Remind /
Suggest** — directive verbs that tell the *reviewer* what to do. That is
consistent with this skill's guidance: they direct a check, they don't
assert an absolute the feature can't guarantee. Still avoid **always /
never / must / mandatory** phrasing aimed at the *code* — prefer
"check that", "flag when", or an `Ask:` question. (`validate-instructions.sh`
lints for the absolute forms, not for Ensure/Verify/Check.)

## What to copy vs. what to leave

Copy the **structure and techniques** above. Do **not** copy GitLab's
group contents — they encode GitLab.com's scale limits (50 GB / 100 GB
table caps), its Cells architecture, its CE/EE split, and its internal
tooling. Your file should encode *your* project's equivalents, discovered
via the review-then-author workflow in `SKILL.md`.
