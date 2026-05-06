---
name: gitlab-pipeline
description: Use when designing or implementing GitLab CI/CD pipelines — covers .gitlab-ci.yml structure, rules and workflow, includes/templates, caching and artifacts, parallel and DAG jobs, environments, OIDC auth to AWS, multi-account deploys, secrets handling, and review apps
---

# GitLab CI/CD Pipeline Design

## Overview

A production GitLab pipeline must be four things at once: declarative,
fast, deterministic, and observable. Most pipelines fail on "fast" and
"deterministic". The fixes are nearly always the same: cache lockfile
artifacts deliberately, use `needs:` for DAG ordering, gate the whole
pipeline with `workflow:rules:`, and split the YAML into focused includes
instead of one 800-line file.

This skill covers the patterns that hold up under the load of multiple
teams pushing dozens of MRs per day, where minutes per pipeline turn into
hours of waiting and small misconfigurations become hard outages.

## When to Use

Reach for this skill when:

- Designing a new pipeline from scratch and choosing the file layout.
- Refactoring an existing pipeline that is slow, flaky, or hard to read.
- Adding deploys (especially to AWS, GCP, Azure) and removing static
  cloud credentials from CI variables.
- Sharing CI patterns across many repos via includes or CI/CD Components.
- Adding review apps, multi-environment promotion, or manual prod gates.
- Diagnosing duplicate-pipeline issues on merge requests.

Skip this skill for application-level concerns (build script logic, test
authoring) and use the language-specific skills instead.

## File Structure and Includes

The root `.gitlab-ci.yml` should be thin. It declares stages, the
workflow rules, and pulls in the actual job definitions. Anything beyond
~150 lines of root file is a refactor signal.

```yaml
# .gitlab-ci.yml
include:
  - local: .gitlab/ci/workflow.yml
  - local: .gitlab/ci/build.yml
  - local: .gitlab/ci/test.yml
  - local: .gitlab/ci/deploy.yml
  - project: platform/ci-templates
    ref: v3.2.0
    file:
      - /templates/aws-oidc.yml
      - /templates/security-scans.yml
  - template: Security/SAST.gitlab-ci.yml

stages:
  - build
  - test
  - scan
  - deploy
```

The four include forms each have a job:

- `include: local` — paths inside this repo. Use for the bulk of the
  pipeline.
- `include: project` — pull templates from a sibling repo. Pin `ref:` to
  a tag, never `main`. Group-owned `platform/ci-templates` is the
  canonical home.
- `include: remote` — arbitrary HTTPS URL. Rare; only for vendor-hosted
  templates that aren't on a GitLab project.
- `include: template` — built-in GitLab templates (`Security/SAST`,
  `Jobs/Code-Quality`, etc.). Cheap to adopt, easy to override.

CI/CD Components (GitLab 17+) supersede ad-hoc project includes for
shared building blocks. A component lives in a project under
`templates/<name>/template.yml`, is versioned by tag, and consumed with
inputs:

```yaml
include:
  - component: $CI_SERVER_FQDN/platform/ci-components/docker-build@1.4.0
    inputs:
      image: $CI_REGISTRY_IMAGE
      dockerfile: ./Dockerfile
      context: .
```

Components beat copy-paste includes because inputs are typed, the
interface is explicit, and consumers pin a semver. Treat them like any
other versioned dependency.

## Stages and Jobs

The default stages (`build`, `test`, `deploy`) are a starting point, not
a rule. Real pipelines often look like:

```yaml
stages:
  - prepare
  - build
  - test
  - scan
  - publish
  - deploy
  - verify
```

A pure stage-based pipeline runs every job in stage N before any job in
stage N+1 starts. That serialises unrelated work. `needs:` builds a DAG:
each job runs as soon as its declared dependencies finish.

Stage-only:

```yaml
unit_tests:
  stage: test
  script: ./run-unit.sh

integration_tests:
  stage: test
  script: ./run-integration.sh

lint:
  stage: test
  script: ./run-lint.sh

# Everything in `test` waits for everything in `build` to finish.
# `lint` waits for the slow `integration_tests` to finish before deploy starts.
```

DAG with `needs:`:

```yaml
build_app:
  stage: build
  script: make build
  artifacts:
    paths: [dist/]

unit_tests:
  stage: test
  needs: [build_app]
  script: ./run-unit.sh

integration_tests:
  stage: test
  needs: [build_app]
  script: ./run-integration.sh

lint:
  stage: test
  needs: []                    # no deps, starts immediately
  script: ./run-lint.sh

deploy_dev:
  stage: deploy
  needs: [unit_tests, lint]    # does not wait for integration_tests
  script: ./deploy.sh dev
```

`needs: []` lets a job start at pipeline creation time, ignoring stages.
Useful for fast linters that should fail the pipeline early.

## Rules — the Most-Misunderstood Feature

`only/except` is deprecated. Use `rules:` everywhere. Rules evaluate top
to bottom; the first match wins; if none match, the job is skipped.

Key clauses:

- `if:` — expression against CI variables.
- `changes:` — paths that, if modified, satisfy the rule.
- `exists:` — file globs that must exist in the repo.
- `when:` — `on_success` (default), `on_failure`, `always`, `manual`,
  `never`, `delayed`.
- `allow_failure:` — let the pipeline continue if this job fails.

### Common patterns

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

### `workflow:rules:` — gating the pipeline itself

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

This is the canonical fix for "ghost pipelines on every push". The fourth
clause kills any pipeline that didn't match the first three.

To skip pipelines for documentation-only commits at the workflow level:

```yaml
workflow:
  rules:
    - if: $CI_COMMIT_TITLE =~ /^docs:/
      when: never
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

## Variables and Secrets

Predefined CI variables worth knowing by heart:

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

### Variable scopes and flags

Variables can be set at instance, group, or project level. Three flags
matter:

- **Masked**: GitLab masks the value in job logs. Required for any
  secret. The value must satisfy mask rules (single line, no special
  chars in some older versions).
- **Protected**: only exposed to jobs running on protected branches or
  protected tags. Required to prevent a feature branch from exfiltrating
  prod credentials.
- **File**: GitLab writes the value to a temp file and exposes the path
  via the variable. Useful for kubeconfigs, service-account JSON, and
  any multi-line secret.

For a real secret, "masked + protected" is the floor, not a nice-to-have.
A masked-only variable can be read by any feature-branch pipeline.

### External vault integration

For anything beyond a handful of secrets, integrate with a real secret
store. HashiCorp Vault example using GitLab JWT auth:

```yaml
get_db_password:
  id_tokens:
    VAULT_ID_TOKEN:
      aud: https://vault.example.com
  secrets:
    DB_PASSWORD:
      vault: ops/data/db/prod@kv
      file: false
  script:
    - psql "postgres://app:${DB_PASSWORD}@db.example.com/app"
```

For AWS, Secrets Manager and Parameter Store are reachable as soon as
OIDC is in place — see the next section.

### Never echo secrets

`echo $DB_PASSWORD` for "debugging" is a hard no, even with masking.
Masking is best-effort; it relies on string equality. If a secret is
base64-encoded, JSON-wrapped, or split across lines it leaks in cleartext.

## OIDC and Cloud Auth

The single largest pipeline-security upgrade in the last few years is
OIDC federation: GitLab issues a short-lived JWT to the job, the cloud
provider trusts that JWT, and the job assumes a role with no static
credentials anywhere.

### AWS

Trust policy on the IAM role (one-time setup, in IaC):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789012:oidc-provider/gitlab.example.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "gitlab.example.com:aud": "https://gitlab.example.com"
      },
      "StringLike": {
        "gitlab.example.com:sub": "project_path:platform/payments:ref_type:branch:ref:main"
      }
    }
  }]
}
```

The `sub` claim is the important condition. Format is documented but the
common shapes are:

- `project_path:GROUP/PROJECT:ref_type:branch:ref:main` — main branch only.
- `project_path:GROUP/PROJECT:ref_type:tag:ref:v*` — release tags.
- `project_path:GROUP/PROJECT:ref_type:branch:ref:*` — any branch (loose).
- `project_path:GROUP/PROJECT:environment:production` — only jobs whose
  `environment.name` is `production`. This is the cleanest pattern for
  multi-environment trust.

Reusable template job:

```yaml
.aws-auth:
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: https://gitlab.example.com
  before_script:
    - >
      STS_RESPONSE=$(aws sts assume-role-with-web-identity
        --role-arn "${AWS_ROLE_ARN}"
        --role-session-name "gitlab-${CI_PROJECT_ID}-${CI_JOB_ID}"
        --web-identity-token "${GITLAB_OIDC_TOKEN}"
        --duration-seconds 3600)
    - export AWS_ACCESS_KEY_ID=$(echo "$STS_RESPONSE" | jq -r .Credentials.AccessKeyId)
    - export AWS_SECRET_ACCESS_KEY=$(echo "$STS_RESPONSE" | jq -r .Credentials.SecretAccessKey)
    - export AWS_SESSION_TOKEN=$(echo "$STS_RESPONSE" | jq -r .Credentials.SessionToken)
    - aws sts get-caller-identity
```

Consumers extend it:

```yaml
deploy_dev:
  extends: .aws-auth
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::111111111111:role/gitlab-deploy-dev
  environment: { name: dev }
  script:
    - aws s3 sync ./dist s3://app-dev-static/
```

### GCP and Azure

Same shape, different ceremony:

- **GCP Workload Identity Federation**: configure a workload identity
  pool, map the `sub` claim to a service account, and call
  `gcloud auth login --cred-file=` against a credential config file
  written from the OIDC token.
- **Azure Workload Identity**: federated credential on a user-assigned
  managed identity. Use `azure/login@v2` style or `az login --federated-token`.

The pattern is identical: GitLab JWT in, short-lived cloud creds out, no
secrets stored.

## Caching vs Artifacts

Different mechanisms, often confused.

| | `cache:` | `artifacts:` |
|---|---|---|
| Purpose | Speed up subsequent jobs/pipelines | Pass data between stages |
| Lifetime | Until evicted | Until `expire_in` |
| Optional? | Yes — pipeline still works | No — downstream jobs depend on them |
| Scope key | `key:` | Job name |
| Typical content | `node_modules`, `.cargo`, `.terraform` | `dist/`, `coverage/`, `*.deb` |

Cache keyed on lockfile (recompute only when deps change):

```yaml
.node-cache: &node_cache
  cache:
    key:
      files:
        - package-lock.json
    paths:
      - .npm/
    policy: pull-push

install_deps:
  <<: *node_cache
  stage: prepare
  script:
    - npm ci --cache .npm --prefer-offline

unit_tests:
  cache:
    key:
      files: [package-lock.json]
    paths: [.npm/]
    policy: pull        # don't push back from test jobs
  script: npm test
```

`cache:policy: pull` is the right default for everything except the one
job that produces the cache. It avoids race conditions where parallel
jobs all push slightly different caches and the last one wins.

Common cache patterns:

```yaml
# Python
cache:
  key: { files: [requirements.txt, requirements-dev.txt] }
  paths: [.pip-cache/, .venv/]

# Terraform
cache:
  key: terraform-${CI_COMMIT_REF_SLUG}
  paths: [.terraform/]

# Rust / Cargo
cache:
  key: { files: [Cargo.lock] }
  paths:
    - .cargo/
    - target/

# Go
cache:
  key: { files: [go.sum] }
  paths: [.go-cache/]
```

Artifacts pass the build output downstream:

```yaml
build_app:
  stage: build
  script: make build
  artifacts:
    paths: [dist/]
    expire_in: 1 week
    reports:
      dotenv: build.env       # sets variables in downstream jobs
```

## Templates and `extends`

Hidden jobs (leading dot) are not run, only used as bases:

```yaml
.base_node:
  image: node:20
  cache:
    key: { files: [package-lock.json] }
    paths: [.npm/]
  before_script:
    - npm ci --cache .npm --prefer-offline

unit_tests:
  extends: .base_node
  script: npm test

build:
  extends: .base_node
  script: npm run build
  artifacts: { paths: [dist/] }
```

`extends:` accepts a list and merges left-to-right with later entries
winning:

```yaml
e2e_tests:
  extends:
    - .base_node
    - .aws-auth          # adds id_tokens + before_script
  script: npm run test:e2e
```

`extends:` does a deep merge of dicts. YAML anchors (`<<: *foo`) do a
shallow merge and silently lose keys nested under `cache:` or `artifacts:`.
Use `extends:` for everything except literal value reuse.

## Multi-Environment Deploy Pattern

```yaml
.deploy:
  extends: .aws-auth
  script:
    - ./scripts/deploy.sh "$CI_ENVIRONMENT_NAME"

deploy_dev:
  extends: .deploy
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::111111111111:role/gitlab-deploy-dev
  environment:
    name: dev
    url: https://dev.example.com
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy_staging:
  extends: .deploy
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::222222222222:role/gitlab-deploy-staging
  environment:
    name: staging
    url: https://staging.example.com
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
  needs: [deploy_dev]

deploy_prod:
  extends: .deploy
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::333333333333:role/gitlab-deploy-prod
  environment:
    name: production
    url: https://app.example.com
    on_stop: rollback_prod
  resource_group: production
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
      allow_failure: false
  needs: [deploy_staging]

rollback_prod:
  extends: .aws-auth
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::333333333333:role/gitlab-deploy-prod
  environment:
    name: production
    action: stop
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
  script: ./scripts/rollback.sh
```

Why each piece matters:

- `environment:` makes deploys show up in the GitLab Environments UI with
  a clickable URL and history. `CI_ENVIRONMENT_NAME` is then available
  to the script and to OIDC sub-claim conditions.
- `when: manual` + `allow_failure: false` for prod gates the deploy on a
  human click while still failing the pipeline if it errors after click.
- `resource_group: production` serialises prod deploys. Without it, two
  MRs merging within seconds can run two prod deploys in parallel and
  race each other.
- `on_stop:` registers a rollback job tied to the environment, callable
  from the Environments UI.

### Review apps (dynamic environments)

```yaml
review_app:
  stage: deploy
  environment:
    name: review/$CI_MERGE_REQUEST_IID
    url: https://mr-$CI_MERGE_REQUEST_IID.review.example.com
    on_stop: stop_review_app
    auto_stop_in: 1 week
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script: ./scripts/deploy-review.sh "$CI_MERGE_REQUEST_IID"

stop_review_app:
  stage: deploy
  environment:
    name: review/$CI_MERGE_REQUEST_IID
    action: stop
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: manual
  script: ./scripts/teardown-review.sh "$CI_MERGE_REQUEST_IID"
```

`auto_stop_in:` cleans up zombie environments without operator action.

## Multi-Account AWS Deploys

The pattern: separate IAM role per AWS account, parameterise the
assume-role step by environment, pin the `sub` claim trust to the
environment name. The `deploy_dev` / `deploy_staging` / `deploy_prod`
example above is already a multi-account deploy — each environment has
its own `AWS_ROLE_ARN` pointing into a different account.

To go further, drive the role ARN purely from environment variables set
on the GitLab environment:

1. In **Settings > CI/CD > Variables**, scope variables to environments:
   `AWS_ROLE_ARN` with value `arn:...:role/gitlab-deploy-dev` scoped to
   `dev`, another scoped to `staging`, another to `production`.
2. The `.deploy` template stays generic — no hardcoded ARNs in YAML.
3. The IAM trust on each role uses
   `gitlab.example.com:sub: ".../environment:dev"` etc., so the dev role
   refuses to be assumed by a job claiming environment `production` and
   vice versa.

This pairs with infrastructure-as-code that owns the roles. See the
`terragrunt-multi-account` skill for the Terragrunt-side layout that
mirrors this account boundary.

## Performance

### Runners

- **Shared runners**: cheapest; queue contention during peak hours.
- **Group runners**: dedicated capacity for a group; usually right for
  team-owned monorepos.
- **Self-hosted**: needed for VPC-internal deploys, large caches,
  GPU/ARM, or compliance.
- **Tags**: `tags: [aws, arm64]` to pin a job to a specific runner pool.

### Interruptible

```yaml
unit_tests:
  interruptible: true
  script: npm test
```

When a new pipeline starts on the same ref, GitLab cancels older
in-flight pipelines whose jobs are marked interruptible. Apply liberally
to anything before `deploy`. Do **not** mark deploy jobs interruptible —
killing a deploy mid-apply produces split-brain state.

### Retry

```yaml
unit_tests:
  retry:
    max: 2
    when:
      - runner_system_failure
      - stuck_or_timeout_failure
      - scheduler_failure
```

Limit retries to infrastructure-class failures. `retry: 2` with no `when:`
is an antipattern — it silently re-runs flaky tests until one passes,
hiding real bugs.

### Parallel matrix

```yaml
e2e:
  parallel:
    matrix:
      - BROWSER: [chromium, firefox, webkit]
        SHARD:   ["1/3", "2/3", "3/3"]
  script: npx playwright test --project=$BROWSER --shard=$SHARD
```

Nine parallel jobs — three browsers x three shards. Each job sees
`BROWSER` and `SHARD` as plain env vars.

## Quality Gates

### Test reports

```yaml
unit_tests:
  script: pytest --junitxml=report.xml --cov --cov-report=xml
  coverage: '/^TOTAL.*\s+(\d+%)$/'
  artifacts:
    when: always
    reports:
      junit: report.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
```

`coverage:` is a regex applied to job logs; the captured number shows up
in MR widgets. `reports:junit` powers the test failure UI in MRs.

### Security templates

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
  - template: Security/Container-Scanning.gitlab-ci.yml
  - template: Jobs/License-Scanning.gitlab-ci.yml

variables:
  SAST_EXCLUDED_PATHS: "tests, vendor, node_modules"
  SECURE_LOG_LEVEL: info
```

To fail the pipeline on findings (Ultimate-tier feature otherwise):
override the analyzer job to parse its JSON report and exit non-zero on
any high/critical findings, or use `Security/License-Compliance` with a
deny list.

## Common Mistakes

| Mistake | Fix |
|---|---|
| `only/except` in a new pipeline | Use `rules:` |
| AWS keys stored as masked CI variables | OIDC + `assume-role-with-web-identity` |
| Caching build outputs | Move to `artifacts:` |
| No `workflow:rules:`, duplicate MR pipelines | Add the canonical workflow rules block |
| Global `image:` for the whole pipeline | Set `image:` per job |
| Long-running test jobs not `interruptible:` | Add `interruptible: true` outside deploy stage |
| `retry: 2` masking flaky tests | Constrain `retry.when` to infra failures |
| One 800-line `.gitlab-ci.yml` | Split into `.gitlab/ci/*.yml` includes |
| Manual prod deploy without `resource_group:` | Add `resource_group: production` |
| `echo $SECRET` for debugging | Remove; secrets belong in tools, not logs |
| MR pipeline running on docs-only changes | `workflow:rules:` with `if: $CI_COMMIT_TITLE =~ /^docs:/ when: never` |
| Pinning `include: project` to `main` | Pin to a tag (`ref: v3.2.0`) |
| Static `AWS_ROLE_ARN` per job | Scope to GitLab environment, drive via `CI_ENVIRONMENT_NAME` |

## Quick Reference

| Keyword | Purpose |
|---|---|
| `stages:` | Ordered pipeline phases |
| `needs:` | DAG ordering, overrides stage waits |
| `rules:` | Per-job conditional execution |
| `workflow:rules:` | Whether to create the pipeline at all |
| `extends:` | Deep-merge inheritance from a (hidden) base job |
| `include:` | Pull YAML from local, project, remote, or template |
| `cache:` | Speed up future jobs (deps), keyed |
| `artifacts:` | Pass build outputs downstream, expires |
| `id_tokens:` | Mint a GitLab JWT for OIDC |
| `secrets:` | Inject from external vault |
| `environment:` | Track deploys, drive OIDC sub claim |
| `resource_group:` | Serialise jobs sharing a name |
| `interruptible:` | Cancel on newer pipeline |
| `retry:` | Re-run on listed failure classes |
| `parallel:matrix:` | Fan out a job over variable combinations |
| `image:` / `services:` | Container image and sidecars |
| `tags:` | Select runner pool |
| `when:` | `on_success`/`manual`/`always`/`never`/`delayed` |
| `allow_failure:` | Don't fail the pipeline if this job fails |
| `coverage:` | Regex to extract coverage % from logs |
| `artifacts:reports:junit` | Surface test results in MR UI |
| `artifacts:reports:dotenv` | Export variables to downstream jobs |
| `CI_PIPELINE_SOURCE` | `push`, `merge_request_event`, `schedule`, `web`, `api` |
| `CI_ENVIRONMENT_NAME` | Resolved environment name in deploy jobs |
| `CI_COMMIT_REF_SLUG` | URL-safe ref name, useful in cache keys |
