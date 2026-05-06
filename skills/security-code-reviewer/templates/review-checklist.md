# Review Checklist

The reviewer ticks through the items below during phases 1-5. Items not
applicable to the in-scope artifact are marked N/A, not skipped silently.

## Phase 1 — Scope

- [ ] Public-facing or internal? Documented.
- [ ] Handles PII, payments, secrets, or auth tokens? Documented.
- [ ] Multi-tenant? Tenant model documented.
- [ ] Languages, frameworks, runtimes listed.
- [ ] Infrastructure (AWS / GCP / Azure / on-prem / k8s) listed.
- [ ] In-scope artifacts named: diff, service, repo, IaC, CI.
- [ ] Two-line scope statement written into the findings report header.

## Phase 2 — Map Trust Boundaries

- [ ] Every HTTP route handler listed.
- [ ] Every queue/topic consumer listed (SQS, Kafka, EventBridge, ...).
- [ ] Every file-upload / S3-event handler listed.
- [ ] Every deserializer call site listed.
- [ ] Every webhook receiver listed (Stripe, GitHub, Slack, ...).
- [ ] Every WebSocket frame handler listed.
- [ ] Every env var sourced from a less-trusted layer noted.
- [ ] Third-party APIs the app trusts implicitly noted.

## Phase 3 — Walk Each Boundary

For each boundary, the reviewer confirms:

- [ ] No SQL string interpolation; parameterized queries everywhere.
- [ ] No NoSQL operator injection (`req.body` not spread into queries).
- [ ] No `subprocess(... shell=True)` / `exec(string)` / `Runtime.exec(String)`
      with concatenation.
- [ ] No template-string compilation of user input
      (`Environment.from_string(userInput)`).
- [ ] No `eval`, `exec`, `Function(string)` on user input.
- [ ] HTTP clients with user-supplied URL have an allowlist, scheme check,
      no-redirect, and metadata-IP block.
- [ ] No `pickle.loads`, `yaml.load` (must be `safe_load`), `marshal.loads`,
      `ObjectInputStream.readObject`, `BinaryFormatter`, `Marshal.load`,
      `unserialize` on attacker data.
- [ ] JWT verifier pins `algorithms`; signature is verified; secret is not
      hardcoded.
- [ ] Token / session / reset / CSRF generation uses CSPRNG
      (`secrets`, `crypto.randomBytes`, `SecureRandom`, `crypto/rand`).
- [ ] Session ID rotated on login; `HttpOnly`, `Secure`, `SameSite` set.
- [ ] Passwords hashed with bcrypt / argon2id / scrypt — never MD5/SHA*.
- [ ] Every object-id endpoint enforces ownership
      (`WHERE id = ? AND user_id = ?`).
- [ ] Every controller has an authorization decorator/guard.
- [ ] Multi-tenant code derives tenant from the auth token, not a header.
- [ ] No `dangerouslySetInnerHTML` / `innerHTML` / `document.write` /
      `{{ x | safe }}` on user input.
- [ ] State-changing endpoints not on GET; cookie auth has CSRF protection.
- [ ] Filesystem and balance-update operations are atomic
      (no check-then-act races).
- [ ] No hardcoded secrets, no secrets in default values, no secrets in
      logs or error messages, no server secrets in client bundle.

## Phase 4 — Out-of-band Checks

- [ ] `gitleaks detect --log-opts="--all"` run; results reviewed.
- [ ] Dependency scanner run; CVEs triaged (see
      `references/dependency-review.md`).
- [ ] `checkov` / `tfsec` / `trivy config .` run on IaC; results reviewed.
- [ ] `hadolint` / `trivy image` run on container images; results reviewed.
- [ ] CI/CD config reviewed against `references/cicd-review.md`.
- [ ] Logging review: no secrets, PII, or session tokens logged.
- [ ] AWS-specific patterns checked (see `references/aws-code-review.md`):
      bucket scoping, presigned URL TTL, KMS context, cross-account
      `assume_role` ExternalId, Lambda env secrets.

## Phase 5 — Write Findings

- [ ] One finding per issue (grouped only on shared root cause).
- [ ] Each finding uses the layout in `templates/finding-report.md`.
- [ ] Severity assigned via `templates/severity-rubric.md`.
- [ ] Each finding has a reproduction the reviewer has confirmed.
- [ ] Each finding has a corrected-code remediation.
- [ ] Each finding has a CWE/OWASP reference.
- [ ] Report header restates the scope from Phase 1.
