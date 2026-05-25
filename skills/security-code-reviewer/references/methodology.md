# Methodology — The Five Phases

Security review proceeds in five phases. The reviewer ticks through
`assets/review-checklist.md` while doing this.

## Phase 1 — Scope

Before reading any code, the reviewer answers:

- Is the system public-facing or internal? Both threat models exist; the
  reviewer does not assume internal services are safe (lateral movement,
  compromised insider).
- Does it handle PII, payments, secrets, or auth tokens? What is the blast
  radius if compromised?
- Is it multi-tenant? Tenant isolation is its own flaw class.
- What languages, frameworks, and runtimes? (Python+Flask, Java+Spring,
  Node+Express, Go, Rust — each has different default sinks.)
- What infrastructure? (AWS+Lambda, Kubernetes, VMs, serverless framework.)
- What is in scope for this review — the diff, the whole service, the whole
  repo including IaC and CI?

The scope is written down. A two-line scope statement at the top of the
findings report prevents later disputes about coverage.

## Phase 2 — Map Trust Boundaries

A trust boundary is any place untrusted input crosses into trusted code.
Examples:

- HTTP request handlers (`@app.route`, `app.get`, `@RestController`)
- Queue/topic consumers (SQS, Kafka, RabbitMQ, EventBridge)
- File uploads, S3 event handlers
- Deserializers (`pickle.loads`, `JSON.parse` of attacker-controlled data,
  `yaml.load`, `ObjectInputStream`)
- Webhook receivers (Stripe, GitHub, Slack)
- WebSocket frames
- Environment variables sourced from a less-trusted layer (e.g. CI from a
  fork PR)
- Third-party APIs that the application trusts implicitly

The reviewer lists each boundary. The most common mistake is trusting input
that crossed an internal API gateway.

## Phase 3 — Walk Each Boundary

For each boundary, the reviewer checks the relevant flaw classes from
`references/flaw-classes.md`. Input is traced forward: where does it land,
where is it concatenated into a query, where is it written to a file path,
where is it passed to a shell.

The reviewer reads all the way to the sink. A handler that calls a service
that calls a repository that calls a query builder is one logical path; the
vulnerability is at the sink, not the handler.

## Phase 4 — Out-of-band Checks

These do not start at a request boundary but are equally important:

- Secrets in git history (`git log -p | grep -iE 'AKIA|secret|password'` or
  `gitleaks detect --log-opts="--all"`)
- Dependency CVEs (`pip-audit`, `npm audit`, `cargo audit`, `osv-scanner`) —
  see `references/dependency-review.md`
- IaC misconfigurations (`checkov -d .`, `tfsec`, `trivy config .`) — see
  `references/iac-and-containers.md`
- Container/Dockerfile (`hadolint`, `trivy image`) — see
  `references/iac-and-containers.md`
- CI/CD configs — see `references/cicd-review.md`
- Logging review — are secrets, PII, or session tokens logged?

## Phase 5 — Write Findings

The reviewer uses `assets/finding-report.md`. One finding per issue.
Related findings are grouped under a parent only when they share a single
root cause and a single fix. Severity is assigned via
`assets/severity-rubric.md`.

A single finding's quality is judged by whether a developer can read it,
locate the file and line, understand the impact, reproduce the issue, and
apply the suggested fix without further questions.
