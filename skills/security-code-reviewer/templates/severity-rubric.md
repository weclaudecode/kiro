# Severity Rubric

Severity is assigned by impact, exploitability, prerequisites, and scope.
The reviewer reserves Critical for issues that are immediately and broadly
exploitable. Marking everything Critical erodes the team's response.

| Level | Impact | Exploitability | Prerequisites | Scope | Example |
| --- | --- | --- | --- | --- | --- |
| **Critical** | Full compromise: RCE, full data breach, admin privilege escalation | Trivial — public exploit, single request | None — unauthenticated, internet-reachable | Whole system or all tenants | Unauthenticated RCE via `pickle.loads` on a public endpoint; AWS root keys committed to a public repo with active use |
| **High** | Significant compromise: read/write of other tenants' data, authenticated RCE, broad SSRF, hardcoded prod credentials | Straightforward with a known technique | Authenticated user or low-privilege account | One service, multiple tenants, or one privileged user | SQL injection behind login; SSRF reaching the cloud metadata service; IDOR exposing other tenants' invoices; hardcoded production DB password in the repo |
| **Medium** | Limited compromise: stored XSS, CSRF on a state-changing endpoint, IAM over-permission, missing rate limit on auth, missing encryption at rest | Requires user interaction, specific timing, or chained conditions | Authenticated user or victim interaction | One feature or one user at a time | Stored XSS in a profile field; CSRF on `POST /password/change`; IAM role with `s3:*` on a bucket needing only `GetObject`; missing rate limit on `/login` |
| **Low** | Defense weakened, not directly exploitable on its own | Requires another bug to chain | Significant — internal access, multi-step setup | Single header or single response | Missing `Strict-Transport-Security` header; verbose error stack trace returned to client; weak password policy (8 chars, no complexity); missing `SameSite` cookie attribute |
| **Informational** | No direct security impact; defense-in-depth or hygiene | Not exploitable | N/A | N/A | Logging library does not redact `Authorization` header by default; outdated TLS cipher in allowlist that is not negotiated; recommendation to add a CSP |

## Decision Procedure

When unsure between two levels, the reviewer answers:

1. **Can it be triggered without authentication?** If yes, lean toward
   Critical or High.
2. **Does it cross a tenant boundary?** If yes, lean toward High or above.
3. **Is the exploit a single request?** If yes, lean up one level. If it
   needs a victim click or specific timing, lean down one level.
4. **Is there evidence of active exploitation in logs?** If yes, Critical.
5. **Is this defense-in-depth only?** If yes, Low or Informational.
