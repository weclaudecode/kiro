# Quality Gates

## Test reports

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

## Coverage parsing — common regexes

| Tool | Regex |
|---|---|
| pytest-cov | `'/^TOTAL.*\s+(\d+%)$/'` |
| Jest | `'/All files[^\|]*\|[^\|]*\s+([\d.]+)/'` |
| Go | `'/coverage: (\d+\.\d+)% of statements/'` |
| Cargo tarpaulin | `'/(\d+\.\d+)% coverage/'` |
| simplecov (Ruby) | `'/\(\d+\.\d+\%\) covered/'` |

## Security templates

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

Example custom gate parsing a SAST report:

```yaml
sast_gate:
  stage: scan
  needs: [sast]
  image: alpine:3.20
  before_script:
    - apk add --no-cache jq
  script:
    - >
      HIGH=$(jq '[.vulnerabilities[] | select(.severity=="High" or .severity=="Critical")] | length' gl-sast-report.json)
    - if [ "$HIGH" -gt 0 ]; then echo "Found $HIGH high/critical findings"; exit 1; fi
```

## Performance: interruptible, retry, parallel

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

Limit retries to infrastructure-class failures. `retry: 2` with no
`when:` is an antipattern — it silently re-runs flaky tests until one
passes, hiding real bugs.

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

## Runners

- **Shared runners**: cheapest; queue contention during peak hours.
- **Group runners**: dedicated capacity for a group; usually right for
  team-owned monorepos.
- **Self-hosted**: needed for VPC-internal deploys, large caches,
  GPU/ARM, or compliance.
- **Tags**: `tags: [aws, arm64]` to pin a job to a specific runner pool.

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
shallow merge and silently lose keys nested under `cache:` or
`artifacts:`. Use `extends:` for everything except literal value reuse.
