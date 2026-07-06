# Writing effective review instructions

Custom instructions are hints that shape an AI reviewer, not a rules
engine. The difference drives every guideline below.

## The core limitation, and what follows from it

> Custom review instructions are guidance for the AI reviewer, not
> enforced policies. GitLab Duo uses them as context to shape its review,
> but cannot guarantee every instruction is applied in every case.

Consequences:

- **Never** put a security control, compliance requirement, or merge gate
  in an instruction and consider it "handled." If it must be enforced,
  enforce it in CI: SAST/SCA scanners, secret detection, policy-as-code
  (OPA/Conftest, `checkov`), coverage thresholds, required approvals,
  protected branches. The instruction is at most a friendly reminder that
  complements the gate.
- Phrase points as **guidance the model can weigh**, not absolutes it must
  obey. "Prefer X" and "flag when Y" work with the grain of an LLM
  reviewer; "always" and "never" set an expectation the feature cannot
  keep.

## Give Duo the judgment calls, not the mechanical ones

If a formatter or linter already enforces something deterministically in
CI, do **not** repeat it as an instruction — you would spend the
reviewer's attention on noise it will duplicate. Leave to tools:

- Formatting, import order, quote style → `prettier`, `black`, `gofmt`, `rufmt`
- Autofixable lint rules → `eslint --fix`, `rubocop -a`, `ruff`
- Type errors → `tsc`, `mypy`, the compiler

Give Duo what tools *cannot* mechanically decide:

- Is this the right abstraction / does this belong here?
- Is the error handling correct for this failure mode (not just present)?
- Are the tests exercising the risky path, or only the happy path?
- Does this public function's contract match its docstring?
- Is this log line going to be useful at 3am, or is it noise?
- Naming that is *technically valid* but misleading.

## Phrasing: do and don't

| Don't | Do |
| --- | --- |
| "Always flag missing tests." | "Flag new public functions that ship without a corresponding test." |
| "Never allow `any`." | "Prefer a precise type; point out `any` where a real type would fit." |
| "Code must have comments." | "Where logic is non-obvious, check that a brief comment explains the *why*." |
| "Follow best practices." | "Check that boto3 clients are created at module scope, not per-invocation." |
| "Ensure good error handling." | "Flag broad `except Exception` that swallows the error without logging or re-raising." |

Concrete beats abstract. Every point should be checkable against a diff by
someone who has never seen the codebase.

## Structure guidelines

- **Number the points.** Numbered lists read as discrete, actionable
  items and keep the reviewer from blurring them together.
- **One group per coherent scope.** A language, a directory, tests, IaC,
  pipeline files. Scope each with `fileFilters` so guidance only reaches
  the files it applies to.
- **Reserve the unfiltered group** (no `fileFilters`, or `**/*`) for a
  small set of genuinely universal points — e.g. "explain the *why* behind
  each suggestion."
- **Exclude tests from source groups** (`!**/*.test.*`, `!spec/**/*`) and,
  where it helps, give tests their **own** group with test-specific
  guidance (coverage of edge cases, no over-mocking, meaningful
  assertions).
- **Keep groups lean.** 3–7 sharp points per group beats 20 vague ones. A
  wall of instructions dilutes attention and, on large MRs, bloats the
  context the reviewer has to work through.
- **Order by importance.** Put the points you care most about first; the
  guidance notes emphasis helps.

## Patterns from production instruction files

These techniques come from GitLab's own large, battle-tested
`mr-review-instructions.yaml` — dissected in
`real-world-example.md`. They scale a file past a handful of
language groups without losing focus.

- **Group by concern and process, not only language.** The
  highest-value groups police a *workflow or architectural rule* the team
  enforces by hand: database migrations, feature-flag removal, public API
  changes, telemetry/event definitions, i18n, changelog rules. After you
  cover each language, ask "what do we have a runbook or wiki page for that
  reviewers police manually?" and give each its own scoped group. See
  `assets/examples/process-and-architecture.yaml`.
- **Use the Ask / Remind / Suggest pattern.** Beyond flat checks, tell the
  reviewer to pose a *question to the author* (`Ask: "What is the projected
  size of this table?"`) or attach a canonical doc (`Remind: "See <link>"`).
  Use `Ask:` when the answer needs human context the model can't infer, and
  name the escape hatch honestly ("the reviewer can't determine X from code
  alone — routing to human review") instead of pretending a hint enforces it.
- **Condition points on what the diff does.** Scope sub-points inside a
  group with `For <situation>: …` or `When this MR touches <X>, check <Y>`.
  The reviewer then only weighs the sub-points relevant to the actual change,
  so one group can cover a rich domain without nagging on every file.
- **Split a domain into source / heuristics / tests.** A big area like
  authentication reads better as three scoped groups (the source files, the
  policy/reasoning heuristics, and the `*_spec`/test files) than one
  sprawling group — each carries tightly relevant points.
- **Be precise in `fileFilters`.** Pin single files
  (`app/controllers/sessions_controller.rb`) and use filename wildcards
  (`*two_factor*.rb`, `doorkeeper*.rb`) when only certain files matter. For a
  mirrored monorepo, list both trees (e.g. `app/**` and `ee/app/**`).
- **Open with a header + references.** A comment block at the top linking
  your own guideline docs (contributing guide, style guide, ADRs, migration
  rules) documents provenance for the next maintainer and gives groups a
  canonical source to cite. The starter template shows the shape.

Directive verbs — **Ensure / Verify / Check / Flag / Ask / Remind** — are
fine: they tell the *reviewer* to run a check. What to avoid is absolute
phrasing aimed at the *code* (**always / never / must / mandatory**), which
promises enforcement the feature can't deliver.

## Start simple, then tune

1. Ship a small file: an "All Files" group plus one group for your primary
   language.
2. Open a real MR, request Duo, and read the comments. The
   `According to custom instructions in '<name>'` prefix tells you which
   group fired.
3. Tune: tighten globs that over-fire, sharpen points that produced vague
   comments, delete points the reviewer already covers by default, add
   points for the review nits you still make by hand.
4. Only then expand to more languages/areas.

## Instance-, group-, and project-level layering

Instructions from instance, group, and project levels are **additive** —
a project adds to the org baseline, it does not replace it. So:

- Keep shared (group/instance) baselines **short, universal, and
  non-conflicting** — e.g. a `security-baseline` group and a
  "leave rationale on suggestions" group.
- Put stack- and repo-specific detail in the **project** file.
- Avoid two levels giving contradictory guidance for the same files; the
  model receives both and you get muddled reviews.

## Failure modes to avoid

| Symptom | Cause | Fix |
| --- | --- | --- |
| Duo repeats what CI already flags | Instruction duplicates a linter rule | Delete it; trust the gate |
| Comments fire on the wrong files | Over-broad or missing `fileFilters` | Tighten globs; add `!` exclusions |
| Vague, unhelpful comments | Vague instruction points | Rewrite as concrete, diff-checkable checks |
| An important check "never runs" | Treating a hint as a guarantee | Move enforcement to CI; keep the hint as a reminder |
| Review feels noisy / slow | Too many points, huge groups | Prune to the high-value judgment calls |
| Source rules nag on test files | Tests not excluded | Add `!**/*.test.*`, `!spec/**/*`, or a separate tests group |
