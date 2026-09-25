# AWS cost dashboards

## Questions to widgets

Build only the widgets that answer a question someone actually asks.

| Reader question | Widget | In kit |
|---|---|---|
| What did we spend, and is it up? | KPI: total + delta vs previous equal period + sparkline | yes |
| What's our daily burn? | KPI: average daily spend | yes |
| Where will the month land? | KPI: month-end forecast (MTD + 7-day run rate) | yes |
| What's the biggest line item? | KPI: top service/account/env (follows groupBy) | yes |
| How is spend trending, and what's it made of? | Stacked daily bar by service, top 7 + Other | yes |
| Which account/team spends most? | Horizontal bar by account, click to filter | yes |
| What changed? | Top movers: diverging bar of the delta by service | yes |
| Show me the numbers | Breakdown table, groupable by service/account/env/region, with prev/change columns | yes |
| Are we over budget? | Bar + budget `markLine`, or a KPI with a status badge (icon + label) | add |
| Is tagging complete? | KPI: % of spend with an `untagged` environment | add |
| Where is the waste? | Table of idle resources with $/month (from Steampipe `queries/cost/`) | add |
| Did Savings Plans / RIs help? | Line: unblended vs amortized over time (two series, one axis) | add |

## Cost semantics: state which one you show

| Metric | Meaning | Use for |
|---|---|---|
| UnblendedCost | Charged rate at usage time; upfront RI/SP fees land on the purchase day | "What hit the bill", matching the invoice |
| AmortizedCost | Upfront commitments spread over the term | Daily trends and team showback (no spikes on purchase days) |
| NetUnblended / NetAmortized | After discounts (EDP, credits applied as discounts) | Finance reconciliation |

- Put the metric name and currency in the page subtitle. The kit renders `meta.metric`, `meta.currency`, `meta.source`, and the date span.
- Exclude **Credit, Refund, Tax** record types from trend views (they cause jumps unrelated to
  usage), and say so in `meta.notes`. Show them separately if anyone needs them.
- Cost Explorer data is typically finalized ~24h later, and the current day is partial. The kit's
  data ends "yesterday". If you include today, mark it as partial.
- Month boundaries are UTC.

## Deltas and colors

- Spend up is bad: `--delta-up` (critical ink) with ▲ and `+`. Spend down is good: `--delta-down`
  (success ink) with ▼ and `−`. Always compare against an **equal-length previous period**, and state which one ("vs previous 30 days").
- Percent change on a tiny base is noise. Top movers rank by **absolute** $ change, and the table shows both $ and %.
- If the prior value is 0, show "new", not +∞%.

## Environments and accounts

- Environment comes from the account (in a multi-account landing zone) or from the `Environment`
  cost-allocation tag. Pick one and document it in `meta.notes`.
- Unmapped or untagged spend is a first-class row (`unmapped`/`untagged`), never dropped. It is
  often the most actionable number on the page.

## Pairing with the rest of the catalog

- `aws-cost-analyst` agent: pulls actuals from Cost Explorer with call budgeting, and estimates from the Pricing API.
- `steampipe` / `powerpipe-reporting`: waste queries (unattached EBS, idle EIPs, old snapshots),
  priced into $/month, which feed an "add" widget above.
- `aws-solution-architect`: hosting the dashboard (S3 + CloudFront + OAC behind auth).
