<!-- Install to: ~/.kiro/prompts/  OR  <project>/.kiro/prompts/ -->
<!-- Invoke as: @runbook -->

Generate an operational runbook for a Lambda function or service.

Ask me first:
1. What's the service or Lambda name?
2. Where does it live in the repo (so you can read its handler / IaC)?
3. Who owns it (team / on-call rotation)?

Then read the code (handler, IaC, CloudWatch alarms) and produce this
Markdown document. Save it to `docs/runbooks/<service-name>.md` (create
the directory if it doesn't exist).

```markdown
# Runbook: <service-name>

**Owner:** <team>  •  **On-call:** <rotation>  •  **Repo:** <link>

## What it does
<1 paragraph: the business purpose, not the implementation.>

## Architecture (1-line)
<trigger → this service → downstream(s). E.g.
"S3 PutObject → Lambda `ingest-orders` → DynamoDB `orders` + SNS topic `order-events`">

## Critical dependencies
| Dep | Purpose | Failure mode |
|---|---|---|
| ... | ... | ... |

## Alarms (and what to do)
For each CloudWatch alarm wired to this service:
| Alarm | Threshold | Likely cause | First action |
|---|---|---|---|
| ... | ... | ... | ... |

## Common operations
### How to look at recent invocations
<exact CLI command or CloudWatch Logs Insights query>

### How to replay failed events
<exact steps — DLQ redrive, S3 re-upload, etc.>

### How to deploy a hotfix
<reference the pipeline; explicit branch + tag steps if it differs from default>

### How to roll back
<exact steps — revert the merge commit, re-run pipeline, verify metric X recovers>

## Known issues / gotchas
<bulleted; each with a link to the ticket or commit if any>

## Escalation
1. <on-call channel>
2. <secondary>
3. <vendor support if applicable>
```

Fill every section. If you can't find the information, say "TODO: ..."
explicitly so the gap is visible — never make up a CloudWatch alarm name.
