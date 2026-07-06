# mr-review-instructions.yaml — format reference

The authoritative source is the GitLab docs:
<https://docs.gitlab.com/user/gitlab_duo/customize_duo/review_instructions/>.
This reference distills the schema, glob rules, configuration levels, and
version history so you can author a valid file without round-tripping to
the docs.

## Location

The file lives at the repository root:

```
.gitlab/duo/mr-review-instructions.yaml
```

Create the `.gitlab/duo/` directory if it does not exist. Duo reads the
copy on the merge request's **target branch**, so the instructions must be
merged (or present on the base branch) to take effect for a given MR.

## Schema

```yaml
instructions:                       # top-level list, required
  - name: <string>                  # required — group label, shown in comments
    fileFilters:                    # optional — list of globs; omit = all files
      - <glob>
      - "!<glob>"                   # leading ! excludes matches
    instructions: |                 # required — the guidance text (block scalar)
      <numbered hints>
```

### Fields

| Field | Required | Meaning |
| --- | --- | --- |
| `instructions` (top level) | yes | The list of instruction groups. |
| `name` | yes | Human label for the group. Appears verbatim in review comments as `According to custom instructions in '<name>': …`. Make it descriptive. |
| `fileFilters` | no | List of glob patterns. A file is in scope if it matches at least one non-negated pattern and no negated (`!`) pattern. Omit the key entirely to apply the group to every changed file. |
| `instructions` (per group) | yes | The guidance passed to the reviewer. Use a `|` block scalar and number the points. |

Quote glob patterns that start with `*`, `!`, or contain `{}` so YAML does
not misparse them (e.g. `"*.rb"`, `"!**/*.test.rb"`).

## Glob syntax

| Pattern | Matches |
| --- | --- |
| `**/*.rb` | Ruby files in **any** directory (nested included) |
| `*.rb` | Ruby files in the **repo root only** |
| `lib/**/*.rb` | Ruby files under `lib/` and its subdirectories |
| `!**/*.test.rb` | **Excludes** files ending `.test.rb` (negation) |
| `!spec/**/*` | Excludes everything under `spec/` |
| `**/*.{js,jsx}` | Union — `.js` or `.jsx` in any directory (**GitLab 19.1+**) |
| `**/*` | Every file (equivalent to omitting `fileFilters`) |

Rules of thumb:

- `**` crosses directory boundaries; a single `*` does not.
- Negations (`!`) subtract from whatever the non-negated patterns
  selected. A group with **only** negations selects everything *except*
  the excluded set (see the "All Files Except Tests" example).
- Brace unions `{a,b}` require GitLab 19.1 or newer; on older versions,
  list the extensions as separate patterns.

## Configuration levels

Duo merges instructions from every level that applies, most-specific last.

### Project level

The `.gitlab/duo/mr-review-instructions.yaml` in the repo. Always active
when present.

### Group level — GitLab 19.0+

An owner selects a **template project** under
**Settings > General > GitLab Duo features** for a top-level group. That
template project's `.gitlab/duo/mr-review-instructions.yaml` applies to
every project in the group and its subgroups, combined with each
project's own file. Use this for an org-wide baseline (e.g. the
`security-baseline.yaml` content).

### Instance level — GitLab 19.1+ (Self-Managed / Dedicated)

An administrator sets a template project under
**Admin > GitLab Duo > Change configuration**. It merges with group- and
project-level instructions.

Precedence is additive, not override: a project does not *replace* the
group baseline, it *adds* to it. Keep shared baselines short and
non-conflicting so project additions layer cleanly.

## How instructions reach the model

Duo **appends** your instruction groups to its built-in review criteria —
it does not replace them. For each changed file, the groups whose
`fileFilters` match contribute their `instructions` text as extra context.
Guidance is best-effort: the model may not surface every point on every
MR, and it never blocks the pipeline.

## Review comment format

When a custom instruction produces feedback, the comment is prefixed:

```
According to custom instructions in '<name>': <feedback>
```

Duo's standard (non-custom) comments do not carry this prefix, so you can
tell which of your groups is firing — useful when tuning globs and
phrasing.

## Version history

| GitLab version | Change |
| --- | --- |
| 18.1 | GitLab Duo Code Review (non-agentic) generally available |
| 18.2 | Custom instructions introduced (beta, behind `duo_code_review_custom_instructions`, off by default) |
| 18.3 | Feature flag enabled by default |
| 18.4 | Feature flag removed (always on) |
| 19.0 | Group-level template configuration added |
| 19.1 | Instance-level configuration; `{a,b}` union patterns in `fileFilters` |

## Minimal valid file

```yaml
instructions:
  - name: All Files
    instructions: |
      1. Explain the "why" behind each suggestion so the author can learn from it.
```
