# State and filtering

## The model

```
user action -> dispatch(action) -> reducer -> state (choices only)
                                                 |
                  dataset (immutable, loaded once) + state -> selectors (memoized) -> view -> widgets
```

- **State** holds only user choices: `range`, `accounts`, `environments`, `services`, `regions` (an
  empty array means all), and `groupBy`.
- The **dataset** is loaded once and never mutated.
- **Selectors** derive everything: resolved date range, previous period, filtered rows, KPIs, trend
  series, grouped rows, movers.
- **Widgets** read from selectors and dispatch actions. No widget holds its own copy of a filter.

The vanilla `createStore` is Redux-shaped on purpose (`getState`, `dispatch`, `subscribe`, pure
reducer), so the same actions and selectors port directly to RTK.

## Adding a filter (checklist)

1. Add the field to the initial state (`store.js` `initialState` / `filtersSlice.ts` `initialFilters`).
2. Add the reducer case or slice reducer. Validate enum payloads, and ignore anything unknown.
3. Add it to URL hash read/write (`stateFromHash`/`hashFromState` or `filtersFromHash`/`hashFromFilters`).
   Omit default values from the hash so the plain URL stays clean.
4. Apply it in `filterRows` (or `matchesDims`), which is the single row predicate.
5. Render the control in the filter bar. It reads its value from state and dispatches on change.
6. Check that "Reset filters" clears it and that a reload with the hash restores it.

## Adding a metric or widget

Write a selector, not component logic. In vanilla, extend `selectView`, which is memoized on
`(data, state)` identity. In React, add a `createSelector` whose inputs are the **narrowest**
upstream selectors, so a `groupBy` change doesn't recompute the trend. Return stable references
(a shared `EMPTY` array rather than `[]` inline), or React re-renders every time.

## Date ranges

- Presets resolve against `meta.end` (the data's last day), never `new Date()`.
- The previous period is the equal-length window immediately before. If it starts before
  `meta.start`, there is no comparison: show "no prior data", not a fake 0% or -100%.
- Month-end forecast = month-to-date actuals + (trailing 7-day average x remaining days). Label it
  as a run-rate estimate. For an ML forecast use Cost Explorer `get-cost-forecast` and ship it in the data file.
- All dates are `YYYY-MM-DD` strings parsed as UTC. Comparing ISO strings (`r.date >= start`) is
  correct and fast. Never `new Date("2026-09-01")` in local time, which shifts a day west of UTC.

## Cross-filtering

A click on a chart mark or table row dispatches `dimension/toggle` for that entity. Every widget
updates because they all read the same state.

- Toggle, don't replace: clicking twice removes the filter.
- De-emphasize (opacity) rather than hide the unselected marks in the chart that was clicked.
- The filter bar shows the result ("prod-app" / "3 selected"), so the user always sees why the numbers changed.
- Don't cross-filter from the chart whose dimension it is into itself in a way that collapses it to
  one bar with no way back. Opacity handles this.

## URL state

State to hash via `history.replaceState` (no history spam). `hashchange` rehydrates, so hand-edited
URLs and back/forward work. Parse defensively: unknown presets or groupBy values fall back to the
defaults. The hash never reaches the server, which matters for S3/CloudFront: no rewrite rules needed.
