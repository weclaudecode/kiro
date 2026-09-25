# Design system

The kit's look comes from two files: `css/tokens.css` (values) and `css/components.css` (patterns).
The React track mirrors both under `src/styles/`. If you change one copy, change the other.

## Tokens: roles, not values

Components reference **roles** (`var(--surface-1)`, `var(--text-secondary)`), never hex. To change a
color, change the token. Adding a token is fine. Hardcoding a value in a component is not.

| Group | Tokens | Use |
|---|---|---|
| Surfaces | `--page`, `--surface-1`, `--surface-2`, `--border`, `--border-strong` | Page plane, cards, table header/hover, hairlines |
| Ink | `--text-primary`, `--text-secondary`, `--text-muted`, `--accent`, `--focus` | Body, labels, axis text, primary action, focus ring |
| Chart chrome | `--grid`, `--axis` | Gridlines (recessive), baseline |
| Series | `--series-1` ... `--series-8`, `--series-other` | Categorical identity, fixed order |
| Status | `--good`, `--warning`, `--serious`, `--critical`, `--*-text` | State only (alerts, budget breaches), always with icon + label |
| Deltas | `--delta-up`, `--delta-down` | Cost change: up is bad (critical ink), down is good |
| Type | `--font-sans`, `--font-mono`, `--fs-xs` ... `--fs-hero` | System UI sans; no display faces |
| Space | `--sp-1` ... `--sp-6` (4px grid), `--radius`, `--control-h` | All padding/gaps come from the scale |

## Theming

- The OS preference is the default, via `@media (prefers-color-scheme: dark)` guarded by
  `:root:not([data-theme="light"])`. Setting `<html data-theme="light|dark">` overrides it in either direction.
- Dark values are defined in two places (the media query and `[data-theme="dark"]`). Keep them identical.
- The inline `<head>` script applies the saved theme before first paint. It is wrapped in
  `try/catch` because storage can throw in private mode.
- A theme change dispatches `document` event `themechange`. The chart wrapper listens for it (and for
  the media query) and re-renders with freshly read tokens.
- Dark mode is **selected**, not inverted: series use the palette's dark steps, shadows drop, and
  borders become light-alpha.

## Layout

- `.app-main` is a vertical stack. Order: filter bar, KPI row, chart grid, detail table. This is
  most-summarized to most-detailed, top to bottom.
- `.kpi-grid`: `repeat(auto-fit, minmax(200px, 1fr))`, so 4 across on desktop and 1 on phones with no media query.
- `.grid` is 12 columns. Use `.span-12` for the time series and the table, `.span-6`/`.span-6` for
  paired comparisons, and `.span-8`/`.span-4` for a chart plus a side list. Everything collapses to
  12 at 760px (spans 8/4 at 1100px).
- Charts need an explicit height (`.chart` 320px, `.chart-sm` 260px). ECharts cannot size to content.
- Tables scroll horizontally inside `.table-scroll`, never the page. Check `scrollWidth === innerWidth` at 390px.
- The filter bar is sticky on desktop and static on phones, where it would cover the screen.

## Typography and numbers

- Hero figures (KPI values) use proportional figures. Table columns and axis ticks use
  `font-variant-numeric: tabular-nums` (already on `.num` cells) so digits align.
- Right-align numeric columns (`numeric: true` on the column). Left-align text.
- A KPI whose value is a name (e.g. "Top service") uses `text: true`: smaller, one line, ellipsis,
  with the full name in `title`.
- Money: whole units on KPIs, fixed 2 decimals in tables, compact (`$2.1K`) on axes and bar labels.

## Components in `components.css`

`card` / `card-header` / `card-title` / `card-subtitle` / `card-body`, `btn` (`-ghost`, `-primary`),
`input`, `select`, `segmented` (with `aria-pressed`), `multiselect` (native `<details>`), `kpi` +
`delta[data-dir]`, `data-table` (`aria-sort` arrows, sticky header, `tfoot` totals), `pager`,
`bar-cell` (inline share bar), `state[data-kind=error]`, `skeleton` (respects reduced motion),
`badge`, `legend` + `swatch`, and print styles that hide controls.

Before adding a component, check whether one of these composes into it. A new component gets a
class block in `components.css` that uses tokens only.
