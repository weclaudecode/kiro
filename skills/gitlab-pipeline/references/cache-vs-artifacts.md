# Cache vs Artifacts

Different mechanisms, often confused.

| | `cache:` | `artifacts:` |
|---|---|---|
| Purpose | Speed up subsequent jobs/pipelines | Pass data between stages |
| Lifetime | Until evicted | Until `expire_in` |
| Optional? | Yes — pipeline still works | No — downstream jobs depend on them |
| Scope key | `key:` | Job name |
| Typical content | `node_modules`, `.cargo`, `.terraform` | `dist/`, `coverage/`, `*.deb` |

## Cache patterns

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

## Artifacts

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

## `artifacts:reports:*`

Reports power MR widgets and the GitLab UI:

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
`reports:dotenv` exports key=value pairs to downstream jobs as variables.

Common report types:

| Report | Use |
|---|---|
| `junit` | Test failures in MR widget |
| `coverage_report` | Coverage diff in MR |
| `dotenv` | Inject vars into downstream jobs |
| `sast` / `dependency_scanning` / `secret_detection` | Security panel |
| `terraform` | Terraform plan output in MR |
| `codequality` | Code-quality MR widget |
