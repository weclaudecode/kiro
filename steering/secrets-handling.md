<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: always
---

# Secrets Handling

The single rule: **secrets never live in git, ever, even briefly.** Not in
code, not in config, not in `.env` checked into the repo, not in commit
messages, not in MR descriptions.

## Where secrets actually live

| Scope | Store | How code reads it |
|---|---|---|
| AWS runtime (Lambda) | AWS Secrets Manager or SSM Parameter Store (`SecureString`) | `boto3` at cold start, cache for the warm container lifetime |
| GitLab CI | Masked + protected CI/CD variables, or OIDC-assumed role | `$VAR` in pipeline; never `echo $VAR` |
| Local dev (workstation) | `direnv` + a gitignored `.envrc` per project | Shell exports, picked up by tools |
| Cross-project local | `~/.config/claude/secrets.env` (chmod 600), sourced by `~/.zshrc` | `${VAR}` in `~/.kiro/settings/mcp.json` |

## Never

- Hardcode AWS access keys, API tokens, DB passwords, or signing keys
  anywhere in the repo. Use placeholders like `${MY_SERVICE_TOKEN}`.
- Use long-lived AWS keys in CI. Use OIDC → STS `AssumeRoleWithWebIdentity`.
- Print secrets to logs. Powertools' `Logger` redacts known fields — extend
  the redaction list rather than disabling it.
- Commit a `.env` file. The repo's `.gitignore` should have `.env*` and
  `.envrc`.

## When you find one

If a secret is found in git history: rotate it immediately at the source,
then purge from history (`git filter-repo`), then force-push (with the
team's awareness — this is the rare case where coordination beats the
no-force-push rule).
