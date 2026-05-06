# Rules and Workflow

`only/except` is deprecated. Use `rules:` everywhere. Rules evaluate top
to bottom; the first match wins; if none match, the job is skipped.

## Key clauses

- `if:` — expression against CI variables.
- `changes:` — paths that, if modified, satisfy the rule.
- `exists:` — file globs that must exist in the repo.
- `when:` — `on_success` (default), `on_failure`, `always`, `manual`,
  `never`, `delayed`.
- `allow_failure:` — let the pipeline continue if this job fails.

## Common patterns

Run on MR, on default branch, and on tag — but nothing else:

```yaml
.rules:default-pipelines: &default_pipelines
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

unit_tests:
  <<: *default_pipelines
  script: ./run-unit.sh
```

Manual prod deploy, only on a semver tag:

```yaml
deploy_prod:
  stage: deploy
  environment:
    name: production
    url: https://app.example.com
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
      allow_failure: false
  script: ./deploy.sh prod
```

Skip a job for docs-only changes:

```yaml
unit_tests:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        - "**/*.{ts,tsx,js,py,go}"
        - "package.json"
        - "go.mod"
  script: ./run-unit.sh
```

## `workflow:rules:` — gating the pipeline itself

Job-level `rules:` decide whether a job runs. `workflow:rules:` decide
whether the entire pipeline is created. Without it, every push to a
branch with an open MR creates two pipelines: one branch pipeline and
one MR pipeline.

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
    - when: never
```

This is the canonical fix for "ghost pipelines on every push" — the
duplicate-MR-pipeline trap. The fourth clause kills any pipeline that
didn't match the first three.

To skip pipelines for documentation-only commits at the workflow level:

```yaml
workflow:
  rules:
    - if: $CI_COMMIT_TITLE =~ /^docs:/
      when: never
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

## Predefined CI variables worth knowing

| Variable | What it holds |
|---|---|
| `CI_COMMIT_REF_NAME` | Branch or tag name |
| `CI_COMMIT_BRANCH` | Branch name (empty on tag pipelines) |
| `CI_COMMIT_TAG` | Tag name (empty on branch pipelines) |
| `CI_COMMIT_SHA` | Full commit SHA |
| `CI_PIPELINE_SOURCE` | `push`, `merge_request_event`, `schedule`, `web`, `api`, `trigger` |
| `CI_ENVIRONMENT_NAME` | Resolved `environment.name` for deploy jobs |
| `CI_PROJECT_DIR` | Working directory the runner clones into |
| `CI_MERGE_REQUEST_IID` | MR number, only present on MR pipelines |
| `CI_DEFAULT_BRANCH` | Usually `main` |
| `CI_COMMIT_REF_SLUG` | URL-safe ref name, useful in cache keys |
