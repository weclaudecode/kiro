<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern:
  - "**/dashboards/**"
  - "**/dashboard/**"
  - "**/*dashboard*.html"
  - "**/*dashboard*.{js,ts,tsx,css}"
  - "**/src/charts/**"
  - "**/src/store/**"
---

# Frontend Dashboard Conventions

Always-apply rules when editing dashboard code. The how-to, starter kits and references live in the
`frontend-dashboards` skill. Load it before scaffolding or adding a widget.

## Stack
- Default: vanilla HTML/CSS/JS ES modules, no build step, with **ECharts** as the only third-party
  script (exact version plus `integrity` SRI). No jQuery, no CSS frameworks, no chart libraries
  other than ECharts.
- Larger apps: Vite + React 19 + TypeScript `strict` + Redux Toolkit / react-redux 9. Exact-pinned
  versions, typed hooks (`useAppSelector`/`useAppDispatch`), no `any`.
- Data is a static JSON file in the skill's data contract (`schemaVersion: 1`), validated at load.

## State
- The store holds user choices only (range, dimension filters, groupBy). Everything shown is derived
  by memoized selectors. Never store filtered rows, totals or series.
- Filters live in one filter bar above the widgets and are URL-hash synced.
- Component-only UI state (table sort/search/page, popover open) stays local, not in the store.
- Date presets resolve from the data's last day (`meta.end`), never from `new Date()`.

## Styling
- Colors, spacing, type and radii come from `tokens.css` variables. No hex, rgb or px font sizes in
  components or chart options. Add a token if one is missing.
- Light and dark are both required. Dark values are chosen, not inverted. Charts re-read tokens on
  `themechange`.
- Numbers: cached `Intl` formatters; tabular numerals and right alignment in tables; fixed decimals
  per money column; compact notation on axes.

## Charts
- Every chart goes through the kit wrapper (`createChart` / `<EChart>`), with a visible title and an
  `aria-label`.
- Categorical colors come from `--series-1..8` in fixed order, assigned by entity once at load, with
  at most 7 named series plus Other. Color follows the entity, never the rank.
- No dual y-axes. No pies for close values. A single number goes in a KPI card.
- Cost deltas: up = `--delta-up`, down = `--delta-down`, always with an arrow or sign as well.

## Quality gates (before saying done)
- Serve over HTTP and check screenshots at 1440 light, 1440 dark and 390 wide: zero console errors
  and no horizontal page scroll.
- Loading, empty ("no data for these filters") and error (with the fix) states render.
- Keyboard: every control is operable, focus is visible, sort headers expose `aria-sort`.
- Security: data is escaped before `innerHTML` (`esc()`), CSV export guards against formula
  injection, no real cost data in git, hosting sits behind auth.
