# Install and Architecture

## Architecture

Steampipe is an embedded PostgreSQL (a fork of Postgres 14) plus per-cloud
foreign data wrapper plugins. Plugins are versioned Go binaries that
implement the FDW protocol; they live under `~/.steampipe/plugins/`.

The mental model: every cloud resource is a row, every nested attribute is a
column or JSONB field, every account is a schema (or merged via aggregator).

The Turbot ecosystem now has three pieces:

- **Steampipe** — the SQL engine and plugins (the data layer)
- **Powerpipe** — benchmarks, controls, and dashboards on top of Steampipe (replaced Steampipe Mods in 2024)
- **Flowpipe** — HCL pipelines that act on query results (issue creation, remediation, scheduled jobs)

## Install

```bash
# macOS
brew install turbot/tap/steampipe

# Linux (Debian/Ubuntu)
sudo apt install -y curl
curl -LO https://steampipe.io/install/steampipe.sh
sudo sh steampipe.sh

# Container (for CI)
docker run -it --rm \
  -v ~/.aws:/home/steampipe/.aws \
  -v ~/.steampipe/config:/home/steampipe/.steampipe/config \
  turbot/steampipe steampipe query "select name from aws_s3_bucket"
```

Powerpipe and Flowpipe are separate binaries:

```bash
brew install turbot/tap/powerpipe
brew install turbot/tap/flowpipe
```

Powerpipe assumes a running Steampipe instance — start it with
`steampipe service start` first.

## Plugins

Install plugins for the providers needed:

```bash
steampipe plugin install aws
steampipe plugin install gcp
steampipe plugin install azure
steampipe plugin install kubernetes
steampipe plugin install terraform
steampipe plugin install github
steampipe plugin install gitlab
```

## Execution modes

- **Interactive** — `steampipe query` drops into a `psql`-like REPL with
  autocomplete and `.inspect` metadata commands
- **One-shot** — `steampipe query "select name from aws_s3_bucket"` runs once
  and exits, ideal for scripts
- **Service mode** — `steampipe service start` exposes a real Postgres
  endpoint on port 9193 for BI tools, `psql`, Metabase, Grafana

## Service mode

Service mode exposes Postgres on port 9193 with default credentials:

```bash
steampipe service start --show-password
# Database: steampipe
# Host:     localhost
# Port:     9193
# User:     steampipe
# Password: ************
```

Connect anything that speaks Postgres:

- `psql -h localhost -p 9193 -d steampipe -U steampipe`
- DBeaver / TablePlus as a SQL IDE
- Metabase pointed at the Steampipe DB for dashboards backed by live cloud state
- Grafana with the Postgres datasource for time-series-style panels (works
  poorly for fast-changing metrics, well for slow-moving inventory)

## Tables and columns

One table per cloud resource type. Conventions:

- Nested structures (tags, policies, configurations) come back as JSONB columns
- `region` and `account_id` are always present when using multi-region or
  aggregator connections
- Each table has documented partition keys — filtering on them avoids full
  enumeration
- Schema discovery: `\d aws_iam_user` in the REPL, or
  `.inspect aws_s3_bucket` for the Steampipe metadata view

The column for tags is consistently `tags` (a JSONB map). Untyped raw API
output is in `*_raw` or `*_std` columns where applicable. For IAM, the
`policy_std` column normalizes a policy document so SQL can navigate it
without worrying about single-vs-list `Action` fields.

## Persistence

Steampipe never persists — every query is live API calls. For history,
schedule the queries and `\copy` results into S3 / Athena, or push to
Snowflake. Building a real warehouse (Athena/Glue/dbt over historical
Steampipe exports) is overkill for ad-hoc audit work and warranted only
when historical trend reporting is a requirement.
