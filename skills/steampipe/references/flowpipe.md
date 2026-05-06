# Flowpipe — Workflow Automation

Flowpipe is HCL-defined pipelines that can run Steampipe queries and act on
results. It is not a Lambda/Step Functions replacement — think of it as glue
for cloud-native workflows that originate from compliance findings.

## Typical use case

A scheduled compliance check that opens a Jira (or GitLab) issue when a
control fails.

```hcl
pipeline "find_public_buckets" {
  step "query" "scan" {
    database = "postgres://steampipe@localhost:9193/steampipe"
    sql = <<-EOQ
      select account_id, name, region
      from aws_s3_bucket
      where bucket_policy_is_public
    EOQ
  }

  step "http" "create_issue" {
    for_each = step.query.scan.rows
    method   = "POST"
    url      = "https://gitlab.example.com/api/v4/projects/123/issues"
    request_headers = {
      "PRIVATE-TOKEN" = var.gitlab_token
    }
    request_body = jsonencode({
      title       = "Public S3 bucket: ${each.value.name}"
      description = "Found in account ${each.value.account_id}, region ${each.value.region}"
      labels      = "security,compliance,public-bucket"
    })
  }
}

trigger "schedule" "daily_scan" {
  schedule = "0 9 * * *"
  pipeline = pipeline.find_public_buckets
}
```

## Execution modes

Flowpipe runs as a service or one-shot:

```bash
# Service with HTTP API and trigger scheduling
flowpipe service start

# One-shot run of a single pipeline
flowpipe pipeline run find_public_buckets
```

## When not to use it

For complex orchestration with retry policies, durable state, and large
parallelism, prefer Step Functions or a real workflow engine. Flowpipe
shines for short, declarative chains: query Steampipe, transform, hit an
HTTP endpoint, post to Slack.

## Cross-references

Flowpipe pipelines triggered from CI fit naturally with the patterns in
`gitlab-pipeline`. Findings emitted by Flowpipe map to the security
review process described in `security-code-reviewer`.
