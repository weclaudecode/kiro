# Skill-Creator Developer Guide

This guide explains how to drive the four moving parts of `skill-creator` directly: the **generator** (drafting a new skill), the **grader** (scoring outputs against assertions), the **comparator** (blind A/B between two outputs), and the **analyzer** (surfacing patterns or explaining why one version beat another). Each section has the parameters the component accepts, the sample input it expects, and the sample output it produces.

For the conversational workflow (when to do what, how to talk to the user), read `SKILL.md`. This file is the lower-level reference: agent contracts, CLI flags, file layouts, and JSON schemas.

> All paths below are relative to `skills/skill-creator/` unless noted.

---

## 0. Mental model

```
                       ┌──────────────────────┐
                       │  evals/evals.json    │  prompts + assertions
                       └──────────┬───────────┘
                                  │
                ┌─────────────────┼──────────────────┐
                ▼                 ▼                  ▼
        with_skill run     without_skill run    old_skill run
        (executor)         (executor)           (baseline for "improve" mode)
                │                 │                  │
                └────────► outputs/ + transcript ────┘
                                  │
                                  ▼
                        ┌─────────────────┐
                        │ Grader (agent)  │  agents/grader.md
                        └────────┬────────┘
                                 │ grading.json (per run)
                                 ▼
                ┌──────────────────────────────────────┐
                │ aggregate_benchmark.py → benchmark.json │
                └──────────────┬───────────────────────┘
                               │
                  ┌────────────┼─────────────┐
                  ▼            ▼             ▼
            Analyzer    Comparator    generate_review.py
            (patterns)  (blind A/B)   (browser viewer)
                                ▲
                                │
                          Analyzer
                          (post-hoc: why did winner win?)
```

Four roles, two modes for the analyzer:

| Component | Lives in | Mode | Purpose |
|---|---|---|---|
| Generator | `SKILL.md` (workflow) + `references/schemas.md` | conversational | Draft a new skill, run test prompts, iterate. |
| Grader | `agents/grader.md` | subagent | Score assertions against an executor run; flag weak assertions. |
| Comparator | `agents/comparator.md` | subagent | Blind A/B between two outputs of the same eval. |
| Analyzer | `agents/analyzer.md` | subagent (two modes) | (a) Surface patterns across a benchmark, or (b) explain why a comparator winner won. |

---

## 1. Generator — drafting and iterating on a skill

The "generator" isn't a single script — it's the create→test→review→improve loop in `SKILL.md`. The pieces you invoke directly are:

### 1.1 Workspace layout

Place test results in a sibling directory: `<skill-name>-workspace/`.

```
my-skill-workspace/
├── iteration-1/
│   ├── eval-0-extract-table/
│   │   ├── with_skill/
│   │   │   ├── outputs/
│   │   │   │   ├── result.csv
│   │   │   │   └── metrics.json
│   │   │   ├── transcript.md
│   │   │   ├── timing.json
│   │   │   └── grading.json
│   │   ├── without_skill/    # baseline for "create" mode
│   │   │   └── …
│   │   └── eval_metadata.json
│   ├── eval-1-…/
│   ├── benchmark.json
│   └── benchmark.md
├── iteration-2/
└── skill-snapshot/           # only for "improve" mode
```

### 1.2 `evals/evals.json` (the test set)

```json
{
  "skill_name": "pdf-extractor",
  "evals": [
    {
      "id": 1,
      "prompt": "Extract every table from sample1.pdf and write them as CSVs.",
      "expected_output": "One CSV per table found in the PDF",
      "files": ["evals/files/sample1.pdf"],
      "expectations": [
        "At least one .csv file is produced",
        "The CSV column headers match row 1 of the source table",
        "Numeric cells are not quoted strings"
      ]
    }
  ]
}
```

Fields: `id`, `prompt`, `expected_output` (human description), `files` (optional, relative to skill root), `expectations` (assertion strings — added once you draft them).

### 1.3 `eval_metadata.json` (one per eval, per iteration)

```json
{
  "eval_id": 1,
  "eval_name": "extract-table",
  "prompt": "Extract every table from sample1.pdf …",
  "assertions": [
    "At least one .csv file is produced",
    "The CSV column headers match row 1 of the source table"
  ]
}
```

### 1.4 Validating the draft

```bash
python -m scripts.quick_validate <path/to/skill>
```

Checks that `SKILL.md` exists and the frontmatter is well-formed.

### 1.5 Packaging the final skill

```bash
python -m scripts.package_skill <path/to/skill-folder> [output-directory]
```

- **arg 1**: skill directory (must contain `SKILL.md`)
- **arg 2** (optional): output directory; defaults to current dir
- **produces**: `<skill-name>.skill` (a zip)

---

## 2. Grader — scoring assertions

The grader reads an executor's transcript and outputs, decides PASS/FAIL for each assertion with evidence, extracts and verifies claims, and critiques the assertions themselves.

### 2.1 How to invoke

Spawn a subagent and hand it `agents/grader.md` plus these parameters in the prompt:

| Parameter | Required | Description |
|---|---|---|
| `expectations` | yes | List of assertion strings (one per item) |
| `transcript_path` | yes | Path to the executor's markdown transcript |
| `outputs_dir` | yes | Directory containing the executor's output files |

The grader also opportunistically reads `<outputs_dir>/metrics.json`, `<outputs_dir>/../timing.json`, and `<outputs_dir>/user_notes.md` if they exist.

### 2.2 Sample invocation prompt

```
Read agents/grader.md and grade this run.

expectations:
  - "At least one .csv file is produced"
  - "The CSV column headers match row 1 of the source table"
  - "Numeric cells are not quoted strings"
transcript_path: my-skill-workspace/iteration-1/eval-0-extract-table/with_skill/transcript.md
outputs_dir: my-skill-workspace/iteration-1/eval-0-extract-table/with_skill/outputs

Write the result to:
  my-skill-workspace/iteration-1/eval-0-extract-table/with_skill/grading.json
```

### 2.3 Sample output (`grading.json`)

```json
{
  "expectations": [
    {
      "text": "At least one .csv file is produced",
      "passed": true,
      "evidence": "outputs/ contains table_1.csv, table_2.csv"
    },
    {
      "text": "Numeric cells are not quoted strings",
      "passed": false,
      "evidence": "table_1.csv row 4 col 3 contains \"1,250\" (quoted, comma-separated)"
    }
  ],
  "summary": { "passed": 1, "failed": 1, "total": 2, "pass_rate": 0.50 },
  "execution_metrics": {
    "tool_calls": { "Read": 4, "Bash": 6, "Write": 2 },
    "total_tool_calls": 12,
    "errors_encountered": 0
  },
  "timing": { "executor_duration_seconds": 41.2, "total_duration_seconds": 53.1 },
  "claims": [
    {
      "claim": "All numeric cells were normalized to floats",
      "type": "quality",
      "verified": false,
      "evidence": "Comma-thousands strings remain quoted in table_1.csv"
    }
  ],
  "eval_feedback": {
    "suggestions": [
      {
        "assertion": "At least one .csv file is produced",
        "reason": "An empty .csv would also pass — consider checking row count > 0"
      }
    ],
    "overall": "Presence checks dominate; add content-correctness assertions."
  }
}
```

### 2.4 Field contract (matters for the viewer)

The expectations array **must** use the fields `text`, `passed`, `evidence`. Variants like `name`/`met`/`details` will silently render as empty in `generate_review.py`. See `references/schemas.md` for the full schema.

### 2.5 Critique-the-evals behavior

The grader is asked to flag assertions that are trivially satisfied or outcomes that no assertion checks. Keep the bar high — only suggestions the eval author would say "good catch" about. Surfaced via `eval_feedback`.

---

## 3. Comparator — blind A/B between two outputs

The comparator judges which output (A vs B) better satisfies an eval prompt **without** knowing which skill produced which. Used when you need a rigorous "is v2 actually better than v1" answer.

### 3.1 How to invoke

Spawn a subagent and hand it `agents/comparator.md` plus:

| Parameter | Required | Description |
|---|---|---|
| `output_a_path` | yes | Path to first output (file or directory) |
| `output_b_path` | yes | Path to second output (file or directory) |
| `eval_prompt` | yes | The original task that produced both outputs |
| `expectations` | no | Optional list of assertions; used as secondary evidence only |

**Important:** randomize which side is A vs B before invoking, and do not include the skill source in the prompt — the comparator must stay blind.

### 3.2 Sample invocation prompt

```
Read agents/comparator.md and compare these two outputs blindly.

eval_prompt: "Extract every table from sample1.pdf and write them as CSVs."
output_a_path: my-skill-workspace/iteration-2/eval-0/run-A/outputs
output_b_path: my-skill-workspace/iteration-2/eval-0/run-B/outputs
expectations:
  - "At least one .csv file is produced"
  - "Numeric cells are not quoted strings"

Write the result to:
  my-skill-workspace/iteration-2/eval-0/comparison.json
```

### 3.3 Rubric

The comparator builds a two-dimensional rubric and scores each side 1–5 per criterion, then averages to a 1–10 overall.

| Dimension | Default criteria |
|---|---|
| **Content** | correctness, completeness, accuracy |
| **Structure** | organization, formatting, usability |

Criteria adapt to the task (e.g., a PDF form might use "field alignment, text readability, data placement"; a data output might use "schema correctness, data types, completeness").

### 3.4 Sample output (`comparison.json`)

```json
{
  "winner": "A",
  "reasoning": "A produced 2 CSVs with correctly-typed numerics; B produced 2 CSVs but left thousands-comma values as quoted strings.",
  "rubric": {
    "A": {
      "content":   { "correctness": 5, "completeness": 5, "accuracy": 5 },
      "structure": { "organization": 4, "formatting": 5, "usability": 4 },
      "content_score": 5.0, "structure_score": 4.3, "overall_score": 9.3
    },
    "B": {
      "content":   { "correctness": 3, "completeness": 4, "accuracy": 3 },
      "structure": { "organization": 4, "formatting": 4, "usability": 4 },
      "content_score": 3.3, "structure_score": 4.0, "overall_score": 7.3
    }
  },
  "output_quality": {
    "A": { "score": 9, "strengths": ["Correctly-typed numerics"], "weaknesses": ["Header capitalization inconsistent"] },
    "B": { "score": 7, "strengths": ["Clean column ordering"],   "weaknesses": ["Quoted numeric strings"] }
  },
  "expectation_results": {
    "A": { "passed": 2, "total": 2, "pass_rate": 1.00, "details": [ /* ... */ ] },
    "B": { "passed": 1, "total": 2, "pass_rate": 0.50, "details": [ /* ... */ ] }
  }
}
```

`winner` is `"A" | "B" | "TIE"`. Ties should be rare — the comparator is instructed to be decisive.

---

## 4. Analyzer — two modes

The analyzer has two distinct jobs that share one file (`agents/analyzer.md`). Pick the mode based on which input you give it.

### 4.1 Mode A — benchmark pattern analysis

Run after `aggregate_benchmark.py` produces `benchmark.json`. The analyzer surfaces patterns the aggregate stats hide: non-discriminating assertions, flaky evals, time/token tradeoffs.

**Parameters:**

| Parameter | Description |
|---|---|
| `benchmark_data_path` | Path to the in-progress `benchmark.json` |
| `skill_path` | Path to the skill |
| `output_path` | Where to write notes (JSON array of strings) |

**Sample invocation prompt:**

```
Read agents/analyzer.md (the "Analyzing Benchmark Results" section) and produce pattern notes.

benchmark_data_path: my-skill-workspace/iteration-1/benchmark.json
skill_path: skills/pdf-extractor
output_path:    my-skill-workspace/iteration-1/analyzer_notes.json
```

**Sample output (`analyzer_notes.json`):**

```json
[
  "Assertion 'At least one .csv file is produced' passes 100% in both configurations — not discriminating",
  "Eval 3 shows high variance (50% ± 40%) — run 2 had an unusual failure",
  "Without-skill runs consistently fail on numeric typing (0% pass)",
  "Skill adds 13s avg execution time but improves pass rate by 50%",
  "Token usage is 80% higher with skill, primarily due to validation-script output"
]
```

The notes get merged into `benchmark.json` under `notes[]` and rendered in the viewer's Benchmark tab.

**Do not** include skill-improvement suggestions in this mode — that's the improvement step, not benchmarking.

### 4.2 Mode B — post-hoc comparator analysis

Run **after** the comparator has chosen a winner. The analyzer un-blinds the result, reads both skills and both transcripts, and explains *why* the winner won.

**Parameters:**

| Parameter | Description |
|---|---|
| `winner` | `"A"` or `"B"` (from comparison.json) |
| `winner_skill_path` | Path to the winning skill |
| `winner_transcript_path` | Path to the winning run's transcript |
| `loser_skill_path` | Path to the losing skill |
| `loser_transcript_path` | Path to the losing run's transcript |
| `comparison_result_path` | Path to `comparison.json` |
| `output_path` | Where to write `analysis.json` |

**Sample invocation prompt:**

```
Read agents/analyzer.md (the post-hoc section) and analyze why the winner won.

winner: A
winner_skill_path:        skills-archive/pdf-extractor-v2
winner_transcript_path:   my-skill-workspace/iteration-2/eval-0/run-A/transcript.md
loser_skill_path:         skills-archive/pdf-extractor-v1
loser_transcript_path:    my-skill-workspace/iteration-2/eval-0/run-B/transcript.md
comparison_result_path:   my-skill-workspace/iteration-2/eval-0/comparison.json
output_path:              my-skill-workspace/iteration-2/eval-0/analysis.json
```

**Sample output (`analysis.json`):**

```json
{
  "comparison_summary": {
    "winner": "A",
    "winner_skill": "skills-archive/pdf-extractor-v2",
    "loser_skill":  "skills-archive/pdf-extractor-v1",
    "comparator_reasoning": "A produced correctly-typed numerics; B left thousands-comma values quoted."
  },
  "winner_strengths": [
    "Explicit step to strip thousands separators before pandas.to_numeric()",
    "Bundled normalize_numerics.py script — reused unchanged across all 3 evals"
  ],
  "loser_weaknesses": [
    "Instruction 'preserve numeric values' was too vague — agent kept commas in",
    "No bundled normalization script — each eval reinvented its own approach"
  ],
  "instruction_following": {
    "winner": { "score": 9, "issues": ["Skipped optional logging step"] },
    "loser":  { "score": 6, "issues": ["Invented own numeric handling instead of using template"] }
  },
  "improvement_suggestions": [
    {
      "priority": "high",
      "category": "tools",
      "suggestion": "Bundle normalize_numerics.py and reference it explicitly from SKILL.md",
      "expected_impact": "Would eliminate the most common failure mode in iteration-1"
    },
    {
      "priority": "high",
      "category": "instructions",
      "suggestion": "Replace 'preserve numeric values' with: 'Strip thousands separators, convert to float, write as bare numbers (no quotes)'",
      "expected_impact": "Removes ambiguity that caused 3/3 baseline runs to fail"
    }
  ],
  "transcript_insights": {
    "winner_execution_pattern": "Read SKILL.md → Used normalize_numerics.py → Verified → Wrote CSVs",
    "loser_execution_pattern":  "Read SKILL.md → Wrote ad-hoc Python → Skipped verification → Wrote CSVs"
  }
}
```

#### Improvement-suggestion categories and priorities

| Category | Use for |
|---|---|
| `instructions` | Prose changes to SKILL.md |
| `tools` | Scripts/templates/utilities to add or modify |
| `examples` | Example inputs/outputs to include |
| `error_handling` | Guidance for handling failures |
| `structure` | Reorganization of skill content |
| `references` | External docs to add |

| Priority | Meaning |
|---|---|
| `high` | Would likely have changed the comparison outcome |
| `medium` | Would improve quality but may not change win/loss |
| `low` | Marginal improvement |

---

## 5. Supporting scripts (CLI reference)

All scripts are run from the `skill-creator/` directory as modules. `python -m scripts.<name> --help` always works.

### 5.1 `aggregate_benchmark.py`

Aggregate per-run grading into a single `benchmark.json`.

```bash
python -m scripts.aggregate_benchmark <benchmark_dir> \
  --skill-name <name> \
  [--skill-path <path>] \
  [--output benchmark.json]
```

| Arg | Required | Default | Notes |
|---|---|---|---|
| `benchmark_dir` (positional) | yes | — | e.g. `my-skill-workspace/iteration-1` |
| `--skill-name` | no | — | Recorded in `metadata` |
| `--skill-path` | no | — | Recorded in `metadata` |
| `--output, -o` | no | `<benchmark_dir>/benchmark.json` | |

Reads each run's `grading.json` and `timing.json`, computes mean/stddev/min/max per configuration, and emits the schema in `references/schemas.md#benchmark.json`.

### 5.2 `generate_review.py`

Launch the eval viewer (browser-based two-tab review surface).

```bash
python -m scripts.generate_review <workspace> \
  --skill-name <name> \
  [--benchmark benchmark.json] \
  [--previous-workspace ../iteration-N-1] \
  [--port 3117] \
  [--static review.html]
```

| Arg | Required | Default | Notes |
|---|---|---|---|
| `workspace` (positional) | yes | — | e.g. `my-skill-workspace/iteration-1` |
| `--skill-name, -n` | no | — | Header label |
| `--benchmark` | no | — | Shows the Benchmark tab |
| `--previous-workspace` | no | — | Iteration 2+ — shows old outputs + feedback inline |
| `--port, -p` | no | `3117` | |
| `--static, -s` | no | — | Write standalone HTML instead of starting a server (use this when there's no display) |

When the user clicks **Submit All Reviews**, feedback is saved to `feedback.json` in the workspace (or downloaded as a file in `--static` mode).

### 5.3 `run_eval.py`

One-shot trigger evaluation — does Claude actually invoke this skill on the queries?

```bash
python -m scripts.run_eval \
  --eval-set trigger_eval.json \
  --skill-path skills/pdf-extractor \
  --model claude-opus-4-7 \
  [--description "Override description to test"] \
  [--runs-per-query 3] \
  [--num-workers 8] \
  [--timeout 60] \
  [--trigger-threshold 0.5] \
  [--verbose]
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--eval-set` | yes | — | JSON: `[{"query": "...", "should_trigger": true}, …]` |
| `--skill-path` | yes | — | Path to skill directory |
| `--model` | no (run_eval) / yes (run_loop) | — | Use the model that powers the session |
| `--description` | no | from `SKILL.md` | Override to test a candidate description |
| `--runs-per-query` | no | 3 | Higher = more reliable trigger-rate estimate |
| `--num-workers` | no | — | Parallelism for `claude -p` calls |
| `--timeout` | no | — | Per-query timeout in seconds |
| `--trigger-threshold` | no | — | Threshold above which a query counts as triggered |
| `--verbose` | no | off | Stream progress to stderr |

### 5.4 `improve_description.py`

Call Claude to propose a better description from a failing eval result.

```bash
python -m scripts.improve_description \
  --eval-results results.json \
  --skill-path skills/pdf-extractor \
  --model claude-opus-4-7 \
  [--history history.json] \
  [--verbose]
```

| Flag | Required | Description |
|---|---|---|
| `--eval-results` | yes | Output from `run_eval.py` |
| `--skill-path` | yes | Skill directory |
| `--model` | yes | Improvement model |
| `--history` | no | Prior attempts (so it doesn't repeat itself) |
| `--verbose` | no | Stream thinking to stderr |

### 5.5 `run_loop.py`

The full description-optimization loop (run_eval + improve_description in a loop, with a held-out test set).

```bash
python -m scripts.run_loop \
  --eval-set trigger_eval.json \
  --skill-path skills/pdf-extractor \
  --model claude-opus-4-7 \
  --max-iterations 5 \
  --holdout 0.4 \
  --runs-per-query 3 \
  --report auto \
  --verbose
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--eval-set` | yes | — | Same shape as `run_eval`'s |
| `--skill-path` | yes | — | |
| `--model` | yes | — | Use the session's model |
| `--description` | no | from `SKILL.md` | Starting description |
| `--max-iterations` | no | — | Stop after this many improvement rounds |
| `--runs-per-query` | no | — | Triplicate runs by default |
| `--holdout` | no | — | Fraction held out for test (e.g. `0.4`); `0` disables |
| `--trigger-threshold` | no | — | |
| `--num-workers`, `--timeout` | no | — | Parallelism / per-query timeout |
| `--report` | no | `auto` | `auto`=temp HTML; path=write there; `none`=disable |
| `--results-dir` | no | — | Save `results.json`, `report.html`, `log.txt` to a timestamped subdir |
| `--verbose` | no | off | |

The final JSON contains `best_description` — selected by **test** score, not train score, to avoid overfitting. Apply it to `SKILL.md` frontmatter.

### 5.6 `package_skill.py`

```bash
python -m scripts.package_skill <skill-folder> [output-directory]
```

Produces `<skill-name>.skill` (zip). On read-only paths, copy to `/tmp/<skill-name>/` and package from the copy.

### 5.7 `quick_validate.py`

```bash
python -m scripts.quick_validate <skill-folder>
```

Cheap sanity check — verifies `SKILL.md` exists and frontmatter parses.

---

## 6. End-to-end sample: a full grading + benchmark + analysis pass

Assume you have a skill at `skills/pdf-extractor/`, evals at `skills/pdf-extractor/evals/evals.json`, and you've already run two configurations (`with_skill` and `without_skill`) for three evals.

```
pdf-extractor-workspace/iteration-1/
├── eval-0-extract-table/
│   ├── with_skill/{outputs/, transcript.md, timing.json}
│   ├── without_skill/{outputs/, transcript.md, timing.json}
│   └── eval_metadata.json
├── eval-1-…/
└── eval-2-…/
```

**Step 1 — grade every run.** Spawn one grader subagent per run (6 total). Each writes its `grading.json`.

**Step 2 — aggregate.**

```bash
python -m scripts.aggregate_benchmark \
  pdf-extractor-workspace/iteration-1 \
  --skill-name pdf-extractor
```

**Step 3 — analyzer pass (Mode A).** Spawn one analyzer subagent on `benchmark.json` to surface patterns; its notes get merged into `benchmark.json` under `notes[]`.

**Step 4 — launch viewer.**

```bash
python -m scripts.generate_review \
  pdf-extractor-workspace/iteration-1 \
  --skill-name pdf-extractor \
  --benchmark pdf-extractor-workspace/iteration-1/benchmark.json
```

**Step 5 — (optional) blind comparator + post-hoc analyzer.** Only when the user explicitly wants a rigorous "is v2 better than v1" check. Spawn the comparator on a random A/B pairing; once it picks a winner, spawn the analyzer in Mode B with both skills and both transcripts to produce `analysis.json`.

**Step 6 — read `feedback.json`**, improve the skill, bump to `iteration-2/`, and repeat.

---

## 7. Common pitfalls

- **Wrong grading.json field names.** Use `text`/`passed`/`evidence` — variants render as empty in the viewer.
- **Wrong benchmark.json structure.** `configuration` (not `config`); per-run metrics nested under `result` (not at top level). See `references/schemas.md#benchmark.json`.
- **Comparator bias.** Always randomize which side is A vs B, and never include the skill source in the comparator's prompt.
- **Analyzer mode confusion.** Mode A (benchmark) returns a `[]` of strings. Mode B (post-hoc) returns a structured object with `improvement_suggestions`. They live in the same file but are distinct contracts.
- **Description-optimization model mismatch.** `--model` for `run_eval`/`run_loop` must be the model powering the session, otherwise the trigger test doesn't reflect what the user experiences.
- **Lost timing data.** `total_tokens` and `duration_ms` only arrive in the subagent task notification. Save to `timing.json` immediately — they're not recoverable later.
- **Overfit descriptions.** `run_loop.py` picks `best_description` by **test** score, not train, on purpose. Don't override that selection without thinking about it.
