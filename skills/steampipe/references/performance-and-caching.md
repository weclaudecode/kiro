# Performance and Caching

Every query hits a cloud API. Three things matter:

1. **Partition pushdown** — filters on documented partition keys
   (`account_id`, `region`, `instance_id`, `bucket_name`) translate to
   single API calls. Without them, Steampipe enumerates everything.
2. **Throttling** — broad queries across many accounts will hit per-account
   TPS limits. Spread over time or scope down.
3. **Cache** — Steampipe caches results for 5 minutes by default. Re-running
   the same query is free.

## Tactics

- `set search_path = aws_prod` limits a query to one connection instead of
  the aggregator
- `set cache = false` for fresh data on the next query
- `--cache=false` flag on one-shot queries
- `cache_ttl` in `~/.steampipe/config/default.spc` to globally raise/lower
  the TTL

## Inspecting query plans

For very wide queries, run service mode and connect with `psql` so EXPLAIN
works:

```bash
steampipe service start
psql -h localhost -p 9193 -d steampipe -U steampipe
EXPLAIN SELECT * FROM aws_s3_bucket WHERE name = 'example';
```

The plan reveals which qualifiers Steampipe pushed down to the API call vs.
which became Postgres-side filters after a full enumeration.

## Caching controls

| Mechanism | Effect |
|---|---|
| `set cache = false` | Disable for current REPL session |
| `set cache_ttl = 60` | Lower TTL to 60 seconds |
| `--cache=false` | Per-query disable on the CLI |
| `STEAMPIPE_CACHE=false` | Env var, disables across all invocations |
| `cache_ttl` in `default.spc` | Persistent global default |

## Output flags

| Flag | Format |
|---|---|
| `--output json` | Array of row objects, ideal for `jq` |
| `--output csv` | CSV with headers, for spreadsheets / `\copy` |
| `--output table` | Default human-readable |
| `--output line` | One field per line per row, for grep |
| `--output asff` | AWS Security Hub Finding Format (Powerpipe only) |

## CI cache reuse

Cache the `~/.steampipe/plugins/` directory between runs to skip plugin
install. Run `steampipe service start` once if multiple queries run in
the same job.
