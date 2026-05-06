---
name: security-code-reviewer
description: Use when reviewing code, IaC, or CI configs for security issues — produces a structured findings report covering OWASP Top 10, secret leakage, IAM over-permission, injection (SQL/NoSQL/SSRF/RCE), auth/session flaws, dependency CVEs, container/Dockerfile issues, and IaC misconfigurations
---

# Security Code Review

## 1. Overview

Security review is hypothesis-driven, not checklist-driven. The reviewer's job
is to imagine the attacker, find the trust boundaries, and check whether the
code holds at each one. A checklist catches the obvious; a threat model catches
what the team did not think of.

The output is always a structured findings report — never a free-form list of
worries. Each finding must be actionable: a developer should be able to read
the finding, find the exact file and line, understand the impact, reproduce the
issue, and apply the suggested fix.

This skill complements automated tooling. It does not replace SAST (semgrep,
CodeQL, bandit), SCA (snyk, dependabot, pip-audit), secret scanners
(gitleaks, trufflehog), or IaC scanners (checkov, tfsec, trivy config). Run
those first, then use human review to find what they miss: business-logic
flaws, IAM over-permission, secrets in unusual places, TOCTOU races,
authorization bypass, and broken multi-tenant isolation.

## 2. When to Use

Use this skill for:

- **Pull-request review** — a feature branch touching auth, payments, file I/O,
  external HTTP calls, or any new HTTP/queue handler
- **Pre-prod audit** — before a service moves from staging to production, or
  before exposing an internal service to the public internet
- **Post-incident review** — when an incident has happened and the team needs
  to find related weaknesses before attackers do
- **Periodic repo audit** — quarterly or yearly review of a long-lived service
- **Dependency upgrade review** — major framework upgrade (e.g. Django 3 to
  5, Spring Boot 2 to 3) where security defaults may have changed

Do **not** use this skill when:

- An automated tool can answer the question. Run `semgrep --config p/owasp-top-ten`
  before manually grepping for SQL injection. Run `gitleaks detect` before
  manually grepping for `AWS_SECRET_ACCESS_KEY`.
- The codebase has never been scanned. SAST/SCA first; human review second.
- The change is documentation-only or test-only with no production code path.

## 3. Review Methodology

### Phase 1 — Scope

Before reading any code, answer:

- Is the system public-facing or internal? Both threat models exist; do not
  assume internal services are safe (lateral movement, compromised insider).
- Does it handle PII, payments, secrets, or auth tokens? What is the blast
  radius if compromised?
- Is it multi-tenant? Tenant isolation is its own flaw class.
- What languages, frameworks, and runtimes? (Python+Flask, Java+Spring,
  Node+Express, Go, Rust — each has different default sinks.)
- What infrastructure? (AWS+Lambda, Kubernetes, VMs, serverless framework.)
- What is in scope for this review — the diff, the whole service, the whole
  repo including IaC and CI?

Write the scope down. A two-line scope statement at the top of the findings
report prevents later disputes about coverage.

### Phase 2 — Map Trust Boundaries

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

List each boundary. Do not skip the "obvious" ones. The most common mistake is
trusting input that crossed an internal API gateway.

### Phase 3 — Walk Each Boundary

For each boundary, check the relevant flaw classes (Section 5). Trace the
input forward: where does it land, where is it concatenated into a query,
where is it written to a file path, where is it passed to a shell.

Read **all the way to the sink**. A handler that calls a service that calls a
repository that calls a query builder is one logical path; the vulnerability
is at the sink, not the handler.

### Phase 4 — Out-of-band Checks

These do not start at a request boundary but are equally important:

- Secrets in git history (`git log -p | grep -iE 'AKIA|secret|password'` or
  `gitleaks detect --log-opts="--all"`)
- Dependency CVEs (`pip-audit`, `npm audit`, `cargo audit`, `osv-scanner`)
- IaC misconfigurations (`checkov -d .`, `tfsec`, `trivy config .`)
- Container/Dockerfile (`hadolint`, `trivy image`)
- CI/CD configs (workflow file review — see Section 10)
- Logging review — are secrets, PII, or session tokens logged?

### Phase 5 — Write Findings

Use the format in Section 4. One finding per issue. Group related findings
under a parent only when they share a single root cause and a single fix.

## 4. Findings Report Format

Every finding must include:

- **Title** — short, specific. "SQL injection in `OrderRepository.findByUser`"
  not "SQL issue".
- **Severity** — Critical / High / Medium / Low / Informational. Criteria:
  - **Critical** — unauthenticated remote code execution, full data breach,
    privilege escalation to admin, secret leak with active exploitation path
  - **High** — authenticated RCE, IDOR exposing other tenants' data, SQL
    injection, SSRF to metadata service, hardcoded production credentials
  - **Medium** — stored XSS, CSRF on state-changing endpoint, missing rate
    limit on auth endpoint, IAM over-permission, missing encryption at rest
  - **Low** — missing security header, verbose error messages, weak password
    policy, missing HSTS
  - **Informational** — defense-in-depth recommendation, code-quality issue
    with security implications
- **CWE/OWASP reference** — e.g. `CWE-89 (SQL Injection)`, `OWASP A03:2021`
- **Location** — `services/orders/repository.py:42-48`, with the actual
  vulnerable code as a snippet
- **Impact** — what an attacker can do, concretely. Not "may lead to data
  exposure". Say "an unauthenticated attacker can read any user's order
  history by sending `userId=1 OR 1=1` in the query string, returning all
  rows from the `orders` table".
- **Reproduction** — exact steps. A `curl` command, a payload, a unit-test
  snippet that demonstrates the issue.
- **Remediation** — the fix, with a code snippet of the corrected version.
  Address the root cause, not the symptom.
- **References** — CWE link, CVE if applicable, vendor advisory, relevant
  OWASP cheat sheet

### Example Finding

> **Title:** SQL injection in `OrderRepository.find_by_user`
>
> **Severity:** High
>
> **CWE/OWASP:** CWE-89 / OWASP A03:2021 — Injection
>
> **Location:** `services/orders/repository.py:42-48`
>
> ```python
> def find_by_user(user_id: str):
>     query = f"SELECT * FROM orders WHERE user_id = '{user_id}'"
>     return db.execute(query).fetchall()
> ```
>
> **Impact:** An authenticated attacker can read every row in the `orders`
> table, including other users' billing addresses and order totals, by sending
> `user_id=' OR '1'='1` to `GET /api/orders`. The endpoint enforces login but
> not row-level ownership, so the SQL injection bypasses the only access check.
>
> **Reproduction:**
> ```bash
> curl -H "Authorization: Bearer $TOKEN" \
>   "https://api.example.com/api/orders?user_id=%27%20OR%20%271%27%3D%271"
> ```
> Returns 14,302 rows instead of the caller's 3.
>
> **Remediation:** Use a parameterized query. Do not interpolate user input
> into the SQL string under any circumstances.
>
> ```python
> def find_by_user(user_id: str):
>     query = "SELECT * FROM orders WHERE user_id = %s"
>     return db.execute(query, (user_id,)).fetchall()
> ```
>
> Additionally, enforce that `user_id` matches the authenticated principal at
> the controller layer (see related finding on broken access control).
>
> **References:**
> - CWE-89: https://cwe.mitre.org/data/definitions/89.html
> - OWASP SQL Injection Prevention Cheat Sheet

## 5. Application Code — What to Check

### Injection

**SQL.** Look for f-strings, `.format()`, `%`-formatting, or `+` concatenation
into a query string.

```python
# Vulnerable
cursor.execute(f"SELECT * FROM users WHERE name = '{name}'")

# Fixed
cursor.execute("SELECT * FROM users WHERE name = %s", (name,))
```

```javascript
// Vulnerable
db.query(`SELECT * FROM users WHERE id = ${req.params.id}`);

// Fixed
db.query("SELECT * FROM users WHERE id = $1", [req.params.id]);
```

ORMs are not immune — `Model.objects.raw(f"...")` and Sequelize
`literal(userInput)` reintroduce the flaw.

**NoSQL.** MongoDB operator injection occurs when an object body is passed
straight into a query: `User.find(req.body)`. An attacker sends
`{"username":{"$ne": null}, "password":{"$ne": null}}` to bypass auth. Look
for `$where`, `$function`, and any unfiltered object spread into a query.

**Command injection.** Sinks: `os.system`, `subprocess.run(..., shell=True)`,
`subprocess.Popen(..., shell=True)`, Node `child_process.exec` (vs `execFile`),
Java `Runtime.exec(String)` with concatenation, Go `exec.Command("sh", "-c", ...)`.

```python
# Vulnerable
subprocess.run(f"convert {filename} out.png", shell=True)

# Fixed
subprocess.run(["convert", filename, "out.png"], shell=False)
```

**LDAP, XPath.** Same principle: parameterize, escape with library helpers,
do not concatenate.

**Template injection.** `Environment(loader=...).from_string(user_input)` in
Jinja2 is RCE. So is rendering user input as a template body in Twig, Velocity,
Freemarker, ERB, or Handlebars-with-helpers. The fix is to never compile user
input as a template — pass it as data only.

### SSRF

Any HTTP client called with a URL derived from user input is suspect:
`requests.get(url)`, `fetch(url)`, `axios.get(url)`, `httpx`, `urllib`,
`net/http`, `HttpClient`. Specifically check:

- Is there a URL allowlist? (Allowlist beats blocklist — IP encodings,
  redirects, and DNS rebinding defeat blocklists.)
- Is the cloud metadata service blocked? (`169.254.169.254`,
  `fd00:ec2::254`, GCP `metadata.google.internal`, Azure `169.254.169.254`)
- Are redirects followed? A whitelisted domain can redirect to internal IPs
  unless `allow_redirects=False`.
- Is the `file://` scheme accepted? (Local file read.)

```python
# Vulnerable
def fetch_image(url):
    return requests.get(url).content

# Fixed (allowlist + scheme check + no redirects)
ALLOWED_HOSTS = {"images.example.com", "cdn.example.com"}
def fetch_image(url):
    p = urlparse(url)
    if p.scheme not in ("https",) or p.hostname not in ALLOWED_HOSTS:
        raise ValueError("disallowed URL")
    return requests.get(url, allow_redirects=False, timeout=5).content
```

### Deserialization

Treat as RCE primitives unless proven otherwise:

- Python: `pickle.loads`, `cPickle.loads`, `marshal.loads`, `yaml.load`
  (must be `yaml.safe_load`), `shelve` of attacker data
- Java: `ObjectInputStream.readObject`, `XMLDecoder`, Jackson with
  default-typing, SnakeYAML default constructor
- .NET: `BinaryFormatter`, `SoapFormatter`, `LosFormatter`, `NetDataContractSerializer`,
  `JavaScriptSerializer` with type resolver
- PHP: `unserialize`, `phar://` stream wrapper
- Ruby: `Marshal.load`, YAML with `Psych.unsafe_load`

The fix is always: do not deserialize attacker-controlled data with these
primitives. Use JSON with explicit schemas (Pydantic, Zod, Jackson with
strict typing).

### Authentication and Session

Common flaws:

- **JWT signature not verified.** `jwt.decode(token, options={"verify_signature": False})`
  in PyJWT, `jwt.verify` not called in jsonwebtoken, custom split-and-base64
  parsing.
- **`alg: none` accepted.** Library does not pin algorithms — pass
  `algorithms=["RS256"]` (or HS256, but be deliberate). Never accept `none`.
- **Hardcoded JWT secret.** `SECRET = "change-me"` committed to the repo.
- **Weak randomness for tokens.** `Math.random()`, `random.random()`,
  `rand()`, `new Random()` for session IDs, password reset tokens, CSRF tokens,
  invite codes. Use `secrets.token_urlsafe`, `crypto.randomBytes`,
  `SecureRandom`, `crypto/rand`.
- **Session fixation.** Session ID not rotated on login.
- **Cookie flags missing.** `HttpOnly`, `Secure`, `SameSite=Lax|Strict`.
- **Password storage.** MD5, SHA1, SHA256, even salted, are wrong. Use
  bcrypt (cost ≥ 12), argon2id, or scrypt.

```python
# Vulnerable — weak token, predictable
import random
token = str(random.random())[2:]

# Fixed
import secrets
token = secrets.token_urlsafe(32)
```

```javascript
// Vulnerable — alg: none accepted
const payload = jwt.verify(token, secret);

// Fixed — pin the algorithm
const payload = jwt.verify(token, secret, { algorithms: ["RS256"] });
```

### Authorization

- **IDOR.** Object IDs in URLs (`/orders/12345`) without an ownership check.
  The fix is `WHERE order_id = ? AND user_id = ?`, not just
  `WHERE order_id = ?`.
- **Missing `@authorize` checks.** A handler exists but no decorator/guard
  runs. In Spring, look for controllers without `@PreAuthorize`. In Django
  REST Framework, look for views with no `permission_classes`.
- **Multi-tenant bleed-through.** Shared connection pool, shared cache key,
  request-scoped tenant ID set from a header rather than the auth token.
- **Forced browsing.** Admin endpoints reachable without admin role check.

### XSS / Output Encoding

- Server templates with explicit unescape: Jinja2 `{{ value | safe }}`,
  Django `{% autoescape off %}`, ERB `<%== %>`.
- React `dangerouslySetInnerHTML={{__html: userInput}}`.
- Vanilla `element.innerHTML = userInput` or `document.write(userInput)`.
- jQuery `$(el).html(userInput)`.
- Returning user input as `Content-Type: text/html` from an API.

The fix is contextual escaping (HTML-attribute, JS, URL, CSS contexts each
need different encoding) plus a strict CSP as defense-in-depth.

### CSRF

- State-changing GET requests (any GET that mutates server state).
- Cookie-authenticated POST/PUT/DELETE without a CSRF token, double-submit
  cookie, or `SameSite=Lax|Strict` on the auth cookie.
- SPAs that send `Authorization: Bearer ...` from `localStorage` are not
  CSRF-vulnerable in the classic sense but are XSS-leakable — note that
  trade-off.

### TOCTOU

- Filesystem: `os.path.exists(p)` then `open(p)` — symlink swapped between
  the two. Use `O_NOFOLLOW` and operate on file descriptors.
- Database: `SELECT balance` then `UPDATE balance = balance - amount` without
  a transaction or `SELECT ... FOR UPDATE`. Race condition lets a user spend
  the same balance twice.
- Idempotency keys checked then written without an atomic primitive.

### Secrets

- Hardcoded API keys, DB passwords, JWT secrets, signing keys.
- Secrets in default values (`DATABASE_URL = os.getenv("DATABASE_URL", "postgres://prod:realpass@...")`).
- Secrets in logs (`logger.info(f"Auth header: {request.headers}")`).
- Secrets in error messages returned to the client.
- Secrets in client-side bundles (`process.env.SECRET_KEY` in Next.js without
  the `NEXT_PUBLIC_` prefix is a footgun the other way — but check Webpack/
  Vite configs for `define` blocks that bake server secrets into the bundle).
- Secrets in git history even after the file was rewritten.

## 6. AWS-Specific Code Review

Cloud SDKs introduce their own sinks. Look for:

- **Overly broad boto3 parameters.** `s3.list_objects_v2(Bucket=user_bucket)`
  where `user_bucket` is user-controlled — caller can enumerate any bucket
  the role has access to.
- **`s3:GetObject` without ownership validation.** The code reads
  `s3://app-uploads/{user_path}` where `user_path` came from the request and
  was not prefix-validated against the caller's tenant.
- **`assume_role` cross-account without `ExternalId`.** Confused-deputy
  vulnerability. Always pass `ExternalId` for third-party cross-account roles.
- **Pre-signed URLs with long expiry.** `generate_presigned_url(... ExpiresIn=604800)`
  (7 days). Default to minutes, not days. Never pass user-controlled
  `ExpiresIn`.
- **DynamoDB scan with user filter.** `scan(FilterExpression=...)` driven by
  user input is O(table) and lets the user enumerate. Use
  `KeyConditionExpression` against an index, scoped to the caller's tenant
  partition key.
- **SQS/SNS with attacker-controlled queue ARN.** Sending to a user-supplied
  ARN can pivot to other accounts.
- **Lambda environment variables containing secrets.** Use Secrets Manager
  or Parameter Store; environment variables in Lambda are visible to anyone
  with `lambda:GetFunction`.
- **KMS `Decrypt` without `EncryptionContext`.** Loses the audit-trail
  binding between the ciphertext and its intended use.

```python
# Vulnerable — caller controls the prefix
def get_user_file(key):
    return s3.get_object(Bucket="app-uploads", Key=key)

# Fixed — bind to authenticated tenant
def get_user_file(tenant_id, key):
    if not key.startswith(f"tenants/{tenant_id}/"):
        raise PermissionError()
    return s3.get_object(Bucket="app-uploads", Key=key)
```

## 7. IaC Review (Terraform / CloudFormation / CDK)

Common high-impact findings:

- **Public S3 buckets.** Missing `aws_s3_bucket_public_access_block` with all
  four flags `true`; ACL `public-read`; bucket policy `Principal: "*"`.
- **Missing S3 encryption.** No `aws_s3_bucket_server_side_encryption_configuration`.
- **Security groups open to the world on non-HTTP ports.** `0.0.0.0/0` on
  22 (SSH), 3389 (RDP), 3306 (MySQL), 5432 (Postgres), 6379 (Redis), 27017
  (Mongo), 9200 (Elasticsearch).
- **IAM wildcards.** `Action: "*"` or `Resource: "*"` on writeable services
  (`s3:*`, `iam:*`, `kms:*`, `lambda:*`). Read-only wildcards are still bad
  for blast radius but worse for mutating actions.
- **RDS/EBS unencrypted.** `storage_encrypted = false` (or omitted on older
  providers).
- **RDS publicly accessible.** `publicly_accessible = true`.
- **Logs disabled.** CloudTrail not enabled in all regions, VPC Flow Logs
  off, S3 access logging off, RDS logs not exported.
- **Lambda Function URL `AuthType: NONE`.** Anyone on the internet can
  invoke. Use IAM auth or front with API Gateway + authorizer.
- **API Gateway without authorizer.** `authorization = "NONE"` on a method
  that calls a sensitive backend.
- **EKS public endpoint.** `endpoint_public_access = true` without
  `public_access_cidrs` restriction.
- **Secrets in Terraform state.** Plaintext secrets in `.tfvars` committed
  to git, or non-encrypted state backend.

Run `checkov -d .`, `tfsec`, or `trivy config .` first; human review then
catches business-logic IAM (e.g. a role that legitimately needs `s3:GetObject`
but on the wrong bucket pattern).

```hcl
# Vulnerable
resource "aws_security_group_rule" "ingress" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# Fixed
resource "aws_security_group_rule" "ingress" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.bastion_cidr]
}
```

## 8. Container / Dockerfile Review

- **`USER root`** at the end of the Dockerfile (or no `USER` at all — defaults
  to root). Add a non-root user.
- **`apt-get install` without `--no-install-recommends`** and without a
  `rm -rf /var/lib/apt/lists/*` cleanup — bloats the image and the attack
  surface.
- **Secrets in `ENV` or `ARG`.** `ENV API_KEY=...` is baked into the image;
  anyone with pull access reads it. `ARG` survives in build cache and history.
  Use BuildKit `--mount=type=secret`.
- **Build-time secrets in layers.** `RUN curl -H "Authorization: Bearer $TOKEN"`
  with a `--build-arg TOKEN` leaves the token in image history.
- **Base image `:latest`.** Pin to a digest (`@sha256:...`) for reproducibility
  and to prevent supply-chain swaps.
- **No signature verification.** Cosign / sigstore for the base image and
  for produced images.
- **No SBOM.** Generate with `syft` or BuildKit `--sbom=true`; ship with
  the image.
- **`COPY . .` over `COPY --chown` and a `.dockerignore`.** Local secrets
  (`.env`, `.aws/`, `.git/`) end up in the image.

```dockerfile
# Vulnerable
FROM python:latest
COPY . /app
RUN pip install -r requirements.txt
CMD ["python", "app.py"]

# Fixed
FROM python:3.12-slim@sha256:abc123...
RUN useradd --system --uid 1000 app
WORKDIR /app
COPY --chown=app:app requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=app:app . .
USER app
CMD ["python", "app.py"]
```

## 9. Dependency Review

- **Lockfile present and committed.** `package-lock.json`, `yarn.lock`,
  `pnpm-lock.yaml`, `poetry.lock`, `Pipfile.lock`, `Cargo.lock`,
  `go.sum`. Without a lockfile, the install is non-reproducible and a
  transitive package can be swapped silently.
- **Run the relevant scanner.** `pip-audit`, `npm audit`, `yarn audit`,
  `pnpm audit`, `cargo audit`, `bundle audit`, `mix deps.audit`,
  `osv-scanner` (cross-language).
- **Transitive deps.** Direct deps may be clean while a transitive has a
  CVE — scanners check both, but verify by reading the report.
- **Abandoned packages.** Last release > 2 years, no maintainer activity,
  open security issues unanswered. Replace or fork.
- **Typosquats.** `requets` vs `requests`, `colourama` vs `colorama`,
  `cross-env` vs `cross-env-shell`. Diff the dependency list against the
  README'd canonical names.
- **SBOM generation.** `syft`, `cyclonedx-bom`, BuildKit. Required for
  any project shipping to customers under modern compliance regimes.

## 10. CI/CD Config Review

The pipeline is itself an attack surface. A compromised pipeline writes to
prod.

- **Untrusted code with privileged secrets.** PR-from-fork triggers a
  workflow that has access to deploy keys. Fix: gate on
  `pull_request` (not `pull_request_target`) and require maintainer approval
  before secrets are exposed (`environment:` with required reviewers).
- **`pull_request_target` in GitHub Actions.** Runs in the context of the
  base branch with full secrets, but checks out the fork's code by default
  if misconfigured. Almost always wrong; if used, do not check out the PR
  ref or do so without running it.
- **`actions/checkout` of an arbitrary ref then `npm install`.** The fork's
  `package.json` runs install scripts with the privileged token in env. Fix:
  do not run untrusted install scripts in privileged jobs.
- **Pinning by tag, not by SHA.** `uses: some/action@v1` can be re-tagged
  by the action's owner. Pin to a commit SHA: `uses: some/action@abc123...`.
- **Secrets echoed to logs.** `echo "TOKEN=$TOKEN"`, `set -x` with secret
  envs, `curl -v` printing auth headers. Mask or do not log.
- **GitLab CI `rules: when: manual` not gating prod.** A "manual" job that
  any developer can trigger is not a control. Use protected environments
  with required approvers.
- **Self-hosted runners on public internet without isolation.** Long-lived
  runners reused across PRs leak secrets and cached creds across runs. Use
  ephemeral runners (one job per VM) or hosted runners.
- **Workflow file edits not protected.** A repo where any contributor can
  modify `.github/workflows/*.yml` and merge a self-approval is one PR away
  from secret exfiltration. Protect the path with CODEOWNERS + required
  review.
- **`permissions:` not pinned.** GitHub Actions defaults to a broad token
  scope unless the workflow declares `permissions:`. Pin to least-privilege
  per-job.

## 11. Common Mistakes by Reviewers

| Mistake | Why it is wrong | What to do instead |
| --- | --- | --- |
| Stopping at the first finding | One bug rarely lives alone; the same coding pattern often repeats | Complete the walk of every boundary before writing up |
| Marking everything Critical | Inflation makes the team ignore real Criticals | Apply the rubric. Reserve Critical for unauth RCE / full breach |
| Vague descriptions ("could lead to issues") | Developer cannot act on it | Name the data, the path, the payload, the impact |
| Recommending a band-aid | Escaping one input still leaves the next call vulnerable | Fix the root cause: parameterize the query, allowlist the URL |
| Not verifying the finding | Reports false positives erode trust | Reproduce with curl/payload/test before filing |
| Trusting "this is internal-only" | Internal services get exposed by misconfig, lateral movement, SSRF | Threat-model with a compromised-insider assumption |
| Ignoring IaC and CI | Most modern breaches go through cloud config or pipeline | Always include `.github/`, `terraform/`, `Dockerfile` in scope |
| Reviewing only the diff | Diff-only review misses pre-existing flaws the diff exposes more deeply | Read the call sites of changed functions; expand scope when warranted |
| Reporting findings without a fix | Leaves the team to research the fix under time pressure | Provide the corrected code snippet |

## 12. Quick Reference

### Severity rubric

| Severity | Criteria |
| --- | --- |
| Critical | Unauthenticated RCE; full data breach; admin privilege escalation; live exploitation evidence |
| High | Authenticated RCE; SQLi; SSRF to metadata; IDOR exposing other tenants; hardcoded prod credential |
| Medium | Stored XSS; CSRF on state-changing endpoint; IAM over-permission; missing encryption; missing rate limit on auth |
| Low | Missing security header; verbose error; weak password policy; missing HSTS |
| Informational | Defense-in-depth note; code-quality observation with security relevance |

### Common grep patterns

| Looking for | Pattern |
| --- | --- |
| SQL string formatting (Python) | `rg 'execute\((f\|").*\{' --type py` |
| SQL string formatting (JS/TS) | `rg 'query\(\s*\`.*\$\{' --type ts --type js` |
| `shell=True` in subprocess | `rg 'subprocess\.\w+\(.*shell\s*=\s*True'` |
| Unsafe YAML load (Python) | `rg 'yaml\.load\(' --type py` (must be `safe_load`) |
| Pickle load | `rg 'pickle\.loads?\(' --type py` |
| `eval` / `exec` | `rg '\b(eval\|exec)\s*\(' -t py -t js -t ts` |
| `dangerouslySetInnerHTML` | `rg 'dangerouslySetInnerHTML'` |
| `innerHTML` assignment | `rg '\.innerHTML\s*=' -t js -t ts` |
| JWT verify disabled | `rg 'verify_signature.*False\|algorithms.*none'` |
| Math.random for tokens | `rg 'Math\.random\(\)' -t js -t ts` |
| Hardcoded AWS key prefix | `rg 'AKIA[0-9A-Z]{16}'` |
| Wildcard IAM action | `rg '"Action":\s*"\*"'` in JSON; `action\s*=\s*"\*"` in HCL |
| SG open to world | `rg '0\.0\.0\.0/0'` |
| `pull_request_target` | `rg 'pull_request_target' .github/workflows` |
| GitHub Action pinned by tag | `rg 'uses:\s+\S+@v[0-9]' .github/workflows` |
| `USER root` / no USER | `rg '^USER\s+root' Dockerfile*` then check files lacking `USER` |
| Public S3 ACL | `rg 'public-read\|public-read-write'` |
| Plaintext secrets in env | `rg -i '(secret\|password\|api[_-]?key)\s*[:=]\s*["'\'']\w' --type yaml --type env` |

### Recommended tools (run before manual review)

| Concern | Tool |
| --- | --- |
| SAST (multi-language) | `semgrep --config p/owasp-top-ten`, CodeQL |
| Python SAST | `bandit -r .` |
| JS/TS SAST | `eslint-plugin-security`, `semgrep` |
| Secret scan | `gitleaks detect --log-opts="--all"`, `trufflehog` |
| Dep scan | `pip-audit`, `npm audit`, `cargo audit`, `osv-scanner` |
| IaC scan | `checkov -d .`, `tfsec`, `trivy config .` |
| Container scan | `trivy image`, `grype`, `hadolint` for Dockerfile lint |
| SBOM | `syft`, `cyclonedx-bom` |
