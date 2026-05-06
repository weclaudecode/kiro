# Data Store Selection

Match access pattern to data store, not the other way round. The most common architectural mistake is choosing DynamoDB for relational queries or RDS for high-write IoT ingestion.

## Decision matrix

| Store | Use when | Avoid when |
|---|---|---|
| **RDS (Postgres/MySQL)** | Relational, moderate scale, standard OLTP | Need >64 TB, want Aurora's HA story |
| **Aurora (Postgres/MySQL-compatible)** | Relational, want better availability and read scaling than RDS | Tiny workload — RDS is cheaper |
| **Aurora Serverless v2** | Variable load, dev/test, infrequent prod with burst | Steady high load — provisioned Aurora is cheaper |
| **DynamoDB** | Known access patterns, key-value, document, single-digit ms at any scale | Ad-hoc queries, joins, analytics |
| **DocumentDB** | Existing MongoDB workload, document model | Greenfield — DynamoDB usually wins on AWS |
| **ElastiCache (Redis/Memcached)** | Caching, session store, leaderboards, pub/sub | Primary durable store |
| **OpenSearch** | Full-text search, log analytics, observability data | OLTP — it is not a database |
| **Redshift** | Petabyte-scale OLAP, BI workloads, structured analytics | Operational queries, low concurrency |
| **S3 + Athena (+ Glue)** | Data lake, infrequent ad-hoc analytics, schema-on-read | Sub-second queries |
| **Timestream** | Time-series at scale, IoT telemetry | Ad-hoc analytics across dimensions |
| **Neptune** | Graph queries, relationship-heavy data | Anything tabular — overkill |

## Decision questions

- What are the top 3 access patterns and their QPS / latency targets?
- Do queries join across entities? If yes, lean relational.
- Is the access pattern stable or evolving rapidly? DynamoDB punishes evolution; Postgres tolerates it.
- What is the consistency requirement — strong, read-after-write, eventual?
- What is the durability and backup story — PITR, cross-region, retention?
- What does failover look like — and has anyone tested it?

## Data store selection at a glance

| Need | Service |
|---|---|
| Relational, moderate scale | RDS Postgres/MySQL |
| Relational, high availability and read scale | Aurora |
| Relational, variable load | Aurora Serverless v2 |
| Key-value, document, predictable access pattern | DynamoDB |
| Cache, session store | ElastiCache Redis |
| Full-text search, log analytics | OpenSearch |
| Petabyte OLAP, BI | Redshift |
| Schema-on-read data lake | S3 + Glue + Athena |
| Time-series at scale | Timestream |
| Graph | Neptune |
