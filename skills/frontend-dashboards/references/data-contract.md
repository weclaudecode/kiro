# Data contract (schemaVersion 1)

Both kits load one JSON file, `data/costs.json`: flat daily rows plus a metadata envelope.
Flat rows keep every export source trivial to map, and let the browser aggregate any way the UI needs.

```json
{
  "meta": {
    "schemaVersion": 1,
    "source": "cost-explorer | csv | sample | steampipe",
    "metric": "UnblendedCost | AmortizedCost | NetAmortizedCost | ...",
    "currency": "USD",
    "granularity": "DAILY",
    "start": "2026-05-28",
    "end": "2026-09-24",
    "generatedAt": "2026-09-25T02:00:00+00:00",
    "notes": "Credits, refunds and tax excluded."
  },
  "rows": [
    { "date": "2026-09-24", "accountId": "111111111111", "accountName": "prod-app",
      "environment": "prod", "service": "Amazon Bedrock", "region": "us-east-1", "cost": 212.41 }
  ]
}
```

| Field | Rule |
|---|---|
| `date` | `YYYY-MM-DD`, the UTC usage day |
| `accountId` | 12-digit string (keep leading zeros, so never a number) |
| `accountName`, `environment` | From Organizations/tags or an `accounts.json` map. Use `"unmapped"` rather than dropping rows |
| `service` | AWS billing name. The UI shortens it for display (`awsServiceLabel`) |
| `region` | Region code, `"global"`, or `"all"` when the source can't split it |
| `cost` | Number in `meta.currency`. Zero rows omitted. Negative allowed only if you deliberately include credits |

The kits validate at load (`prepare()`): wrong `schemaVersion`, a missing field, or a non-numeric
cost raises a `DataError`, which renders the error state with the reason. When you change the
contract, bump `schemaVersion` and update `prepare()`, `to_rows.py validate`, and `types.ts` together.

## Producing the file

### Sample data (prototyping, screenshots, tests)

```bash
python3 scripts/gen_sample_costs.py --days 120 --end 2026-09-24 --spike -o data/costs.json
```
Seeded, so output is stable. `--spike` triples prod Bedrock spend over the last 6 days, which is
useful for checking that movers, deltas, and forecasts tell the story.

### Cost Explorer (actuals, $0.01 per API call)

Cost Explorer allows **two** group-bys, so group by account and service, then map accounts to
names and environments with a small `accounts.json`:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-06-01,End=2026-09-25 --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=LINKED_ACCOUNT Type=DIMENSION,Key=SERVICE \
  --filter '{"Not":{"Dimensions":{"Key":"RECORD_TYPE","Values":["Credit","Refund","Tax"]}}}' \
  > ce-page1.json
# If the response has NextPageToken, repeat with --next-page-token and pass every page file.
python3 scripts/to_rows.py ce ce-page*.json --accounts accounts.json -o data/costs.json
python3 scripts/to_rows.py validate data/costs.json
```

`End` is exclusive. Region comes out as `"all"`. For environment directly from a cost-allocation
tag, group by `Type=TAG,Key=Environment` + `SERVICE` instead and adapt the mapping. The
`aws-cost-analyst` agent covers call budgeting.

### CUR 2.0 via Athena (actuals at any grain, cheapest at scale)

Alias columns to contract names and download the result CSV:

```sql
SELECT
  date_format(line_item_usage_start_date, '%Y-%m-%d')          AS "date",
  line_item_usage_account_id                                   AS "accountId",
  line_item_usage_account_name                                 AS "accountName",
  coalesce(nullif(resource_tags['user_environment'], ''), 'untagged') AS "environment",
  line_item_product_code                                       AS "service",
  coalesce(nullif(product_region_code, ''), 'global')          AS "region",
  round(sum(line_item_unblended_cost), 4)                      AS "cost"
FROM cur2
WHERE billing_period BETWEEN '2026-06' AND '2026-09'
  AND line_item_line_item_type IN ('Usage', 'DiscountedUsage', 'SavingsPlanCoveredUsage')
GROUP BY 1, 2, 3, 4, 5, 6
```
```bash
python3 scripts/to_rows.py csv athena-results.csv --metric UnblendedCost -o data/costs.json
```

Check the column names against your own export's schema before running this. CUR 2.0 column
names, the tag key format (`user_<tag>`), and the partition column (`billing_period`) depend on how
the export and its Glue table were set up. `line_item_product_code` yields codes like `AmazonEC2`,
not billing names. Extend `AWS_SHORT` in `format.js`/`format.ts` with those codes if you use them.

### Steampipe / Powerpipe

Any `steampipe query --output csv` whose columns are aliased to the contract names works with
`to_rows.py csv`. See the `steampipe` skill's `queries/cost/` for starting points.

## Size and hosting

- ~10k rows is ~1.6 MB raw and ~150 KB gzipped. The browser aggregates this instantly.
- Past ~200k rows or ~20 MB, pre-aggregate upstream (drop `region`, go weekly, or ship per-view summary files).
- Static hosting: S3 (private) + CloudFront with OAC, gzip/brotli on. Cost data is sensitive, so put
  it behind auth (CloudFront + Cognito/Lambda@Edge, or an internal ALB with OIDC). Never use a public bucket.
- Don't commit real cost exports to git. Commit the generator, not the data.

## Loading, empty, and error states

| State | What the user sees |
|---|---|
| Loading | Skeleton KPI tiles (shimmer, disabled under reduced motion) |
| 404 | "No data at data/costs.json. Generate it: ..." |
| `file://` | "Serve the folder: python3 -m http.server 8000" |
| Bad shape | The validation message with the offending row |
| Filters match nothing | KPIs at $0, table says "No data for the current filters", charts empty. The filter bar still works |
| No previous period | Delta replaced by the period text. Movers say "No previous period in the data" |
