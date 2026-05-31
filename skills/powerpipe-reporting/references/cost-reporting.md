# Cost reporting via the AWS cost MCP servers

Powerpipe/Steampipe see **resource state** (what exists, what's idle), not
your **bill**. For actual dollars, use two AWS Labs MCP servers, registered
in `mcp/mcp.sample.json` and inherited by agents with `includeMcpJson: true`.

| Server | Module (uvx) | Answers | Cost |
|---|---|---|---|
| `aws-pricing` | `awslabs.aws-pricing-mcp-server` | "What *would* this cost?" (unit/list prices) | **Free** |
| `cost-explorer` | `awslabs.cost-explorer-mcp-server` | "What *did* env X cost?" (actual spend) | **$0.01 per Cost Explorer API call** |

Both are read-only and use standard AWS credential resolution
(`AWS_PROFILE`, `AWS_REGION`). In the sample, **pricing is enabled** and
**cost-explorer ships `disabled: true`** — flip it on deliberately when you
need actuals (see `docs/mcp-guide.md`).

## aws-pricing (free) — estimate before you build

Tools (names may evolve; discover via `/tools`):

- `get_pricing` — price for a service/SKU under given attributes/region.
- `get_pricing_service_codes` / `get_pricing_service_attributes` /
  `get_pricing_attribute_values` — discover what to filter on.
- `generate_cost_report` — assemble an estimate across components.

Use it for: sizing a new environment, comparing instance families,
"what does moving this NAT/EBS/RDS to X cost", pre-deploy estimates in an MR.

## cost-explorer (paid) — what each environment actually spent

Tools:

- `get_today_date` — anchor relative date ranges.
- `get_dimension_values` — discover values for `SERVICE`, `REGION`, etc.
- `get_tag_values` — discover values for a tag key (e.g. `Environment`).
- `get_cost_and_usage` — spend for a period, grouped/filtered.
- `get_cost_and_usage_comparisons` — baseline vs comparison period (Δ).
- `get_cost_forecast` — ML forecast for budget planning.

### The $0.01 rule — spend discipline

Every Cost Explorer API request bills **$0.01**, and complex queries can be
several requests. So:

- **Group by the `Environment` tag**, don't loop one call per account.
- Prefer **MONTHLY** granularity; reserve DAILY for a flagged anomaly.
- Pin an explicit start/end; don't re-pull history you already have.
- Keep the server's `autoApprove: []` so each billable call prompts — no
  silent charges mid-conversation.
- For dashboards refreshed often, cache the CE result to a file and read
  that; don't re-query on every render.

### Per-environment spend — the canonical query

This is the FinOps headline number: cost grouped by the `Environment` tag.

> Ask the agent (it drives `get_cost_and_usage`):
> "Monthly UnblendedCost for the last 3 months, grouped by tag
> `Environment`." → one call, returns dev/staging/prod side by side.

Requires that resources are tagged `Environment=dev|staging|prod` and the
tag is **cost-allocation-activated** in the Billing console. If untagged,
fall back to grouping by `LINKED_ACCOUNT` (one account per environment).

## Estimate vs actual — when to use which

| Question | Server | Why |
|---|---|---|
| "What will this new RDS cost?" | pricing | No spend exists yet; free |
| "Why did prod jump 20% this month?" | cost-explorer (`…_comparisons`) | Needs real billing data |
| "Forecast next month's dev spend" | cost-explorer (`get_cost_forecast`) | ML on your history |
| "Cheapest region for this workload?" | pricing | Compare list prices, free |
| "Per-environment spend this quarter" | cost-explorer (`get_cost_and_usage` by `Environment`) | Actuals by tag |

## Tying cost to Powerpipe waste

The strongest report combines both: Powerpipe lists the *idle* resources
(unattached EBS, idle EIPs, old snapshots) and pricing turns each into a
**$/month wasted** figure — a concrete savings number per environment. The
`aws-cost-analyst` agent is set up to do exactly this.
</content>
