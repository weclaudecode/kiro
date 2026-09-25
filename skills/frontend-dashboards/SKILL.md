---
name: frontend-dashboards
description: Use when building or changing a data dashboard in the browser with HTML, CSS and JavaScript (or React + TypeScript + Redux Toolkit) - KPI/stat cards, ECharts charts, data tables with sort/filter/search/pagination/CSV export, filter bars, cross-filtering, light/dark theming. Canonical example is an AWS cost analysis dashboard fed by static JSON/CSV exported from Cost Explorer, CUR/Athena or Steampipe. Ships two runnable starter kits (zero-build vanilla, and Vite + React 19 + TS + RTK/react-redux 9), design tokens, a validated chart palette, and data scripts. Not for Powerpipe HCL dashboards (use powerpipe-reporting) or server-side APIs.
---

# Frontend Dashboards

## Overview

A dashboard answers a small set of recurring questions at a glance, then lets the reader drill in.
Quality comes from four things, in this order: **the right question per widget**, **one state model
with derived data**, **a design system instead of ad-hoc styling**, and **verification in a real
browser**. This skill ships working code for all four; start from the kit, don't write from scratch.

Canonical example: AWS cost analysis - total spend with period-over-period delta, month-end forecast,
daily spend stacked by service, spend by account, top movers, and a grouped breakdown table.

## Pick a track first

| Situation | Track | Start from |
|---|---|---|
| One page, static JSON/CSV, < ~10 widgets, hosted on S3/CloudFront or opened locally | **Vanilla** (default) | `assets/vanilla/` |
| Multi-page app, many interacting widgets, existing React codebase, or a team maintaining it | **React + TS + Redux Toolkit** | `assets/react/` |

Default to vanilla. It has no build step and no dependency upgrades, and the only third-party code
is one pinned, SRI-checked chart library. Move to React when the page outgrows one file of wiring,
not before. Both tracks share the data contract, design tokens, state shape, and selector logic, so
moving from vanilla to React is a port, not a redesign.

Redux Toolkit earns its place here only because filters are **shared state read by every widget**
(cross-filtering). Table sort/search/page state stays local to the table component. Do not add Redux
to a single-widget page. Read `references/react-redux.md` before changing the React store.

## Workflow

1. **Data first.** Get a contract file (`references/data-contract.md`). No real data yet? Generate
   sample data: `python3 scripts/gen_sample_costs.py --spike -o <kit>/data/costs.json` (React:
   `public/data/costs.json`, or `npm run sample-data` with a global install). Real exports: `scripts/to_rows.py ce|csv`.
   Always finish with `python3 scripts/to_rows.py validate <file>`.
2. **Copy the kit** into the project and run it:
   - Vanilla: `python3 -m http.server 8000` in the kit folder. `file://` will not work because ES
     modules and `fetch()` are blocked there.
   - React: `npm install && npm run dev`; `npm run build` must pass (it runs `tsc --noEmit`).
3. **Decide the widgets** from the questions the reader asks (`references/aws-cost-dashboards.md`
   for cost; `references/charts.md` for picking the form). Remove kit widgets that answer no one's
   question.
4. **Build with the kit's components.** Add state as reducer actions, add derived data as selectors,
   and render through the chart wrapper, table, and KPI components. Style only with tokens.
5. **Verify in a browser.** Run the checklist in `references/quality-checklist.md`: light, dark, and
   390px widths, no console errors, every filter path, empty/error states, and CSV export. Take a
   screenshot and look at it before calling it done.

## Non-negotiables

- **Derived, not stored.** State holds only user choices (range, dimension filters, groupBy). Totals,
  series, and table rows come from memoized selectors. Never copy filtered data into state.
- **One filter bar, above everything it filters.** Filters are URL-synced (hash) so views are shareable.
- **Date ranges resolve against the data's last day**, not `new Date()`. A static export is a snapshot.
- **Color follows the entity.** Assign series slots once at load, by total over the full dataset.
  Filtering never repaints a survivor. Use at most 7 named series plus "Other", never a generated 9th hue.
- **Tokens only.** No hex in components or chart code. Charts read CSS variables at render time and
  re-render on theme change. Build dark mode deliberately from the token set; never invert light colors.
- **No dual-axis charts. No pies for close values.** A single number is a KPI card, not a chart.
- **Cost deltas: up = red, down = green**, and each one also carries an arrow/sign and text. Color is never the only signal.
- **Escape all data** going into `innerHTML` (`esc()` in vanilla; React escapes by default). CSV
  export guards against formula injection. Pin and SRI-hash every CDN script.
- **Loading, empty, and error states are designed**, not left blank. The error message tells the
  user the fix, e.g. "Generate it: ...".

## Kit contents

| Path | What it is |
|---|---|
| `assets/vanilla/index.html` | Page shell: header, filter bar, KPI row, 3 charts, breakdown table |
| `assets/vanilla/css/tokens.css` | Design tokens, light + dark, validated categorical palette (mirrored in React) |
| `assets/vanilla/css/components.css` | Card, grid, controls, multiselect, KPI, table, pager, states (mirrored in React) |
| `assets/vanilla/js/store.js` | `createStore` + reducer + URL hash sync (Redux-shaped, zero deps) |
| `assets/vanilla/js/data.js` | Load + validate, `resolveRange`, `previousRange`, memoized `selectView` |
| `assets/vanilla/js/format.js` | Cached `Intl` currency/percent/date formatters, `delta()`, `esc()`, `awsServiceLabel()` |
| `assets/vanilla/js/components/` | `chart.js` (ECharts wrapper), `table.js`, `kpi.js`, `filters.js` |
| `assets/react/` | Same dashboard: Vite 8, React 19, TS 7 strict, RTK 2 + react-redux 9.3, tree-shaken ECharts 6 |
| `assets/react/src/store/` | `filtersSlice`, `dataSlice` (async thunk), `selectors` (`createSelector`), typed hooks |
| `assets/react/src/components/` | `EChart`, `DataTable<T>`, `KpiCard`, `FilterBar`, `Card`, `ThemeToggle` |
| `assets/react/src/charts/` | Pure option builders + `useChartTokens()` theme hook |
| `scripts/gen_sample_costs.py` | Deterministic, realistic AWS cost sample data (`--spike` injects an anomaly) |
| `scripts/to_rows.py` | Cost Explorer JSON / CUR-Athena CSV to contract; `validate` subcommand |

## References (load only what the task needs)

| File | Load when |
|---|---|
| `references/design-system.md` | Styling, layout, spacing, typography, dark mode, adding a token |
| `references/charts.md` | Choosing a chart, writing an ECharts option, palette rules, upgrading ECharts |
| `references/data-tables.md` | Table features, large row counts, column formatting, CSV export |
| `references/state-and-filtering.md` | Adding a filter, cross-filtering, URL state, new derived metrics |
| `references/react-redux.md` | Anything in the React track: store shape, selectors, typed hooks, pitfalls |
| `references/data-contract.md` | Data shape, exporting from Cost Explorer / CUR 2.0 via Athena / Steampipe |
| `references/aws-cost-dashboards.md` | Cost semantics (unblended/amortized, credits), which widgets answer which question |
| `references/quality-checklist.md` | Before calling any dashboard done: a11y, perf, security, browser verification |

## Common mistakes

| Mistake | Fix |
|---|---|
| Opening `index.html` via `file://` and seeing a blank page | Serve it: `python3 -m http.server` |
| "Last 30 days" computed from today on a month-old export | Resolve ranges from `meta.end` |
| Series colors assigned by current rank | Freeze `colorSlot` at load (already done in both kits) |
| Filter state duplicated in a component and the store | One source: the store. Components dispatch |
| Table sort/page state in Redux | Local component state; only cross-widget state goes in the store |
| Formatting numbers with `toFixed` / string concat | Use `format.js` / `format.ts` (locale, currency, compact) |
| Mixed decimals in a money column (`$634.97` next to `$2,069`) | Fixed 2 decimals in tables; compact on axes and labels |
| New `Intl.NumberFormat` per cell | Cached formatters |
| `echarts.init` scattered across features | Always the wrapper (`createChart` / `<EChart>`) |
| Unpinned CDN script (`echarts@latest`) | Exact version + `integrity` hash |
| Shipping without looking at it | Screenshot light/dark/mobile, then fix label clipping and overflow |
