---
name: gitlab-duo-review
description: Use when configuring GitLab Duo Code Review (the non-agentic reviewer) for a project — reviews a repository's structure, technology stack, and team workflows, then authors a tailored .gitlab/duo/mr-review-instructions.yaml with scoped, per-language instruction groups. Covers the YAML schema, fileFilters glob syntax, group/instance-level templates, phrasing best practices, and the reviewer's limitations.
---

# GitLab Duo Custom MR Review Instructions

## Overview

GitLab Duo Code Review (non-agentic) is the reviewer you request on a
merge request by assigning `@GitLabDuo` or commenting
`/assign_reviewer @GitLabDuo`. It reads the MR title, description, diffs,
filenames, and the pre-change file contents, then leaves inline review
comments. **Custom review instructions** are a per-repository file —
`.gitlab/duo/mr-review-instructions.yaml` — that *append* your team's
standards to Duo's built-in review criteria, scoped to file globs.

This skill's job is to produce that file well. The instructions file is
only as good as how faithfully it captures the project: its languages,
its layout, its conventions, and the review nits humans keep repeating.
So the workflow is **review-then-author** — inspect the repo first, then
write instruction groups that match what is actually there.

Custom instructions are **guidance, not policy.** Duo treats them as
context to shape a review; it cannot guarantee every instruction fires on
every MR. Never rely on them for security controls, compliance gates, or
anything that needs deterministic enforcement — those belong in CI
(SAST/SCA, policy-as-code, required approvals), not in a reviewer hint.
Requires GitLab 18.1+ with the GitLab Duo Enterprise add-on (Premium or
Ultimate).

## When to Use

- Standing up GitLab Duo Code Review on a repo for the first time and
  writing its `mr-review-instructions.yaml`.
- A team keeps leaving the same review comments by hand (naming, error
  handling, test coverage, "did you add a changelog entry") and wants Duo
  to catch them.
- Onboarding a polyglot monorepo where each language/area needs different
  review emphasis, scoped by path.
- Setting a **group- or instance-level template** project so many repos
  inherit a shared baseline, then layering per-project additions.
- Auditing or refactoring an existing instructions file that has grown
  noisy, over-broad, or full of "always/never" mandates the reviewer
  cannot honor.

Skip this skill for enforceable controls (use CI quality gates — see the
`gitlab-pipeline` and `security-code-reviewer` skills), and for the
*agentic* Code Review Flow in the Duo Agent Platform, which is a separate
feature with its own configuration.

## The review-then-author workflow

Author instructions in five steps. Do not skip step 1 — instructions
written without reading the repo are generic and low-value.

1. **Map the repo.** Detect languages, frameworks, and the directory
   layout. `scripts/detect-stack.sh <repo>` gives a fast inventory
   (extensions by count, framework/manifest markers, test dirs, IaC/CI
   presence) and prints suggested `fileFilters` globs to seed groups. Read
   any existing `CONTRIBUTING.md`, `.editorconfig`, linter configs
   (`.rubocop.yml`, `.eslintrc`, `ruff.toml`, `.golangci.yml`), and — for
   kiro projects — `.kiro/steering/*` conventions.
2. **Harvest the real conventions.** Turn what you found into concrete,
   checkable review points: the linter's non-autofixable rules, the
   error-handling pattern, the logging/observability convention, the test
   layout and coverage expectation, the changelog/commit rules. Skip
   anything a formatter or linter already enforces in CI — Duo should
   review what tools *cannot* mechanically catch.
3. **Group by file scope — and by concern.** One instruction group per
   coherent area. Cover each language, but the highest-value groups often
   police a *workflow or architectural rule* the team enforces by hand —
   database migrations, feature-flag removal, public API changes,
   telemetry, i18n — scoped to the files that trigger it. Each group gets
   `fileFilters` globs (pin single files or use filename wildcards where
   only certain files matter); put truly universal points in an unfiltered
   "All Files" group. See `references/real-world-example.md` for the
   techniques behind a large production file.
4. **Phrase as hints.** Number the points. Write them as guidance
   ("prefer", "check that", "flag when") — not mandates ("always",
   "never", "must"). Where a check needs author context the model can't
   see, use the `Ask:`/`Remind:` pattern (pose a question, attach a doc
   link) and condition sub-points on the diff (`For <situation>: …`). See
   `references/best-practices.md`.
5. **Validate and place.** Run `scripts/validate-instructions.sh` to
   confirm the schema and globs parse, then write the file to
   `.gitlab/duo/mr-review-instructions.yaml` at the repo root. Open an MR
   and request Duo to sanity-check the comments it produces.

## The file, in one block

```yaml
# .gitlab/duo/mr-review-instructions.yaml
instructions:
  - name: TypeScript Source Files       # shown in the review comment
    fileFilters:                        # optional; omit to match every file
      - "**/*.ts"
      - "!**/*.test.ts"                 # ! excludes
      - "!**/*.spec.ts"
    instructions: |                     # numbered hints, not mandates
      1. Prefer precise types; flag use of `any` where a real type fits.
      2. Check that exported functions have doc comments.
      3. Point out complex logic that lacks a brief explanatory comment.
```

Duo appends these to its standard criteria. When a custom point fires,
the comment reads: *"According to custom instructions in
'TypeScript Source Files': …"*.

## Templates

Start from `assets/mr-review-instructions.yaml` (an annotated starter) and
graft in the example groups that match the project's stack.

| Template | Use for |
| --- | --- |
| `assets/mr-review-instructions.yaml` | Annotated starter with an "All Files" group, glob cheatsheet, and placement note |
| `assets/examples/python-lambda.yaml` | Python / AWS Lambda (Powertools, handler structure, boto3, tests) |
| `assets/examples/terraform-terragrunt.yaml` | Terraform + Terragrunt (IAM scope, state/lifecycle risk, variable validation) |
| `assets/examples/gitlab-ci.yaml` | `.gitlab-ci.yml` pipelines (OIDC vs. static keys, image pins, rules) |
| `assets/examples/kubernetes.yaml` | K8s / EKS manifests (limits, probes, securityContext, IRSA) |
| `assets/examples/frontend-ts.yaml` | TypeScript / React / Node frontends (types, a11y, state, tests) |
| `assets/examples/process-and-architecture.yaml` | Concern/process groups (DB migrations, feature flags, public API, telemetry, i18n) — the `Ask:`/`Remind:` and conditional-scoping patterns |
| `assets/examples/security-baseline.yaml` | Cross-cutting security hints (secrets, input validation, authz) — good group-level template content |

## References

| Reference | Covers |
| --- | --- |
| `references/instruction-format.md` | Full YAML schema, field semantics, glob syntax (incl. `!` negation and `{a,b}` unions), project/group/instance levels, version history, comment format |
| `references/best-practices.md` | Writing effective hints, what to leave to CI, phrasing do/don't, group granularity, the guidance-not-policy limitation, common failure modes |
| `references/review-workflow.md` | How Duo non-agentic review works: requesting it, what it can see, automatic reviews, large-MR handling, model selection, and how custom instructions combine across levels |
| `references/real-world-example.md` | Techniques distilled from GitLab's own large production `mr-review-instructions.yaml` (concern/process groups, `Ask:`/`Remind:`, conditional scoping, concern-splitting, precise filters, header/references) with a link to the source |

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/detect-stack.sh` | Inventory a repo's languages/frameworks/layout and print suggested `fileFilters` globs to seed instruction groups. Read-only. |
| `scripts/validate-instructions.sh` | Validate an `mr-review-instructions.yaml` — schema shape, required fields, glob sanity, and phrasing lint (warns on "always/never/must"). |

## Common Mistakes

| Mistake | Fix |
| --- | --- |
| Writing instructions without reading the repo | Run `detect-stack.sh` and read the conventions first; author from evidence |
| Duplicating what the linter/formatter already enforces | Leave mechanical rules to CI; give Duo the judgment calls tools miss |
| One giant unfiltered group | Split by area with `fileFilters`; reserve the unfiltered group for truly universal points |
| Mandate phrasing ("always flag", "never allow") | Rephrase as hints ("prefer", "check that", "flag when") — Duo can't guarantee mandates |
| Relying on an instruction for a security/compliance gate | Enforce in CI (SAST/SCA, policy-as-code, required approvals); the instruction is at most a reminder |
| `*.rb` expecting it to match nested files | `*.rb` is root-only; use `**/*.rb` for any directory |
| Forgetting to exclude tests from source groups | Add `!**/*.test.*` / `!spec/**/*` so source rules don't fire on test files |
| Vague points ("write good code", "follow best practices") | Make each point concrete and checkable against a diff |
| File in the wrong place | It must be `.gitlab/duo/mr-review-instructions.yaml` at the repo root, on the MR's target branch |
| Huge instruction sets on a huge MR | Keep groups lean; split large MRs — oversized context can degrade or fail the review |

## Cross-references

- `gitlab-pipeline` — enforceable quality gates (SAST/SCA, coverage,
  policy) that belong in CI, not in reviewer hints.
- `security-code-reviewer` — the deep, human-driven security review whose
  repeatable, low-severity checks make good Duo hints (`security-baseline.yaml`).
- The `gitlab-duo-instructions-author` agent loads this skill to author
  the file for a project non-interactively.
