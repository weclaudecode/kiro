# Data tables

Both kits ship a dependency-free table: search, sort, pagination, a totals row, and CSV export.
Vanilla: `createTable(root, options).setRows(rows)`. React: `<DataTable rows rowKey columns ... />`.

## Column definition

```js
{
  key: "cost",            // field on the row object
  label: "Cost",          // header text (also the CSV header)
  numeric: true,          // right-aligned, tabular numbers, first sort click = descending
  total: true,            // sum shown in <tfoot> over the searched view (not just the page)
  render: (v, row) => ..., // vanilla: HTML string (escape it!); React: ReactNode. row is null in the footer
  csv: (v|row) => ...,     // raw export value; round floats here
}
```

## Behavior contract

| Feature | Rule |
|---|---|
| Search | Case-insensitive substring over `searchKeys`. Debounced 150ms (vanilla) or `useDeferredValue` (React). Resets to page 1 |
| Sort | Click a header to toggle. Numbers sort descending first, text ascending first. Nulls sort **last** in both directions. `localeCompare` with `numeric: true` so "m5.2xlarge" < "m5.10xlarge" |
| a11y | `<th scope="col" aria-sort="ascending|descending|none">` with a `<button>` inside. `<caption class="sr-only">`. Live row count (`aria-live="polite"`) |
| Pagination | Clamp the page when rows shrink under it. Show "1-15 of 42". Disable prev/next at the ends |
| Totals | Computed over the whole filtered+searched view. Never sum a percentage column |
| Empty | Distinguish "No data for the current filters" from "No rows match your search" |
| Row click | Optional `onRowClick`. Rows get `tabindex=0`, and Enter/Space trigger it. Used for cross-filtering |
| CSV | Exports the whole filtered+sorted view (all pages), raw values, UTF-8 BOM (Excel), CRLF. Prefixes string cells starting with `= + - @` with `'` (formula-injection guard). Filename includes the data end date |

## State placement

Sort, search, and page are **local** to the table. No other widget cares about them, so they stay
out of the store and the URL. Exception: if people share links to a specific sorted view, add
`sort` to the URL-synced state. The dashboard-level filters arrive already applied via `rows`.

## Formatting

- Fixed decimals per money column (`currency(v, code, { decimals: 2 })`). Mixed `$634.97` / `$2,069` breaks alignment.
- Deltas: signed value plus a `data-dir` color class, with a textual `+`/`−`. Show "n/a" when there
  is no prior period and "new" when the prior was 0.
- The share column gets an inline `.bar-cell` bar. That is cheap and scannable, and it doubles as the "table view" of a share chart.
- Show full AWS service names in tables. Short labels are for axes.

## Scale limits

| Rows in view | Approach |
|---|---|
| < 5,000 | Kit table as is (pagination keeps the DOM small) |
| 5,000 - 50,000 | Still fine: filtering and sorting arrays of this size take milliseconds. Keep `pageSize` <= 50 |
| > 50,000 or wide raw CUR lines | Pre-aggregate upstream (Athena/Steampipe) to the grain the table shows. Don't ship raw line items to the browser |
| Needs column resize/reorder/pinning, virtual scroll, grouping UI | Adopt TanStack Table (headless, React track) instead of growing the kit table. Keep the same column/format conventions |
