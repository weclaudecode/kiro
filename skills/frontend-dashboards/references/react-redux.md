# React + TypeScript + Redux Toolkit track

Versions pinned in `assets/react/package.json`: React 19.3, react-redux 9.3, @reduxjs/toolkit 2.12,
ECharts 6.1, Vite 8.3, TypeScript 7.0 (`strict`, `noUncheckedIndexedAccess`). Pin exact versions and
upgrade deliberately.

## When Redux is (and isn't) the right tool here

| Need | Use |
|---|---|
| Filters read by many widgets, cross-filtering, URL sync | Redux slice (`filtersSlice`) |
| Loaded dataset + request status | Redux slice with `createAsyncThunk` (`dataSlice`) |
| Table sort/search/page, popover open, hover | `useState` in the component |
| Theme | CSS `data-theme` + `useSyncExternalStore` (`charts/theme.ts`), not Redux |
| Server data with caching/refetch/polling (a live API) | RTK Query, not hand-written thunks |

For a single-widget page, `useReducer` + context is enough. Don't add Redux.

## Store layout

```
src/store/
  index.ts          makeStore(hash) -> configureStore; RootState/AppDispatch types; syncFiltersWithUrl
  hooks.ts          useAppDispatch = useDispatch.withTypes<AppDispatch>(); useAppSelector = useSelector.withTypes<RootState>()
  filtersSlice.ts   user choices + hash (de)serialization
  dataSlice.ts      status: idle|loading|succeeded|failed, error, dataset
  selectors.ts      createSelector chain; the only place aggregation happens
```

- `makeStore` is a factory (not a module singleton), so tests can create isolated stores with a preloaded hash.
- The dataset is big and immutable. It is excluded from the dev-mode `immutableCheck` and
  `serializableCheck` (`ignoredPaths: ["data.dataset"]`), which otherwise walk every row on every action.
- The dataset stays plain JSON (`Record`, not `Map`) so it is serializable and DevTools can show it.
- The thunk's `condition` skips a second load. React StrictMode runs effects twice in dev.

## Selector rules

- Components call **narrow** selectors (`selectKpis`, `selectTrend`, `selectMovers`) and never pull
  the whole state or the whole dataset to compute inline.
- Input selectors return existing references (`s.filters.accounts`). Output selectors return new objects only when their inputs change.
- Selecting `s.filters` in one component is fine. Selecting `{ a: s.x, b: s.y }` inline creates a
  new object on every call and forces a re-render on every action. Use two `useAppSelector` calls or a memoized selector.
- Never return a fresh `[]`/`{}` fallback from a selector. Use a module constant (`EMPTY`).

## Component rules

- Chart options are pure functions in `src/charts/options.ts`, memoized with `useMemo` over
  `[tokens, data, formatters]`. Formatters come from `useMoney()` (memoized by currency), so they are referentially stable.
- `<EChart>` inits once and calls `setOption(option, { notMerge: true })` when `option` changes.
  The click handler goes through a ref so a new callback doesn't re-init the chart.
- `useChartTokens()` returns a new object only when the theme flips, so charts re-theme without re-rendering on every action.
- Generic components (`DataTable<T>`, `Column<T>`) are typed by row. `rowKey` supplies stable keys,
  never the array index (sorting would remount rows).
- Widgets live in `App.tsx` as small components (`KpiRow`, `TrendCard`, ...), each with its own
  selectors, so a filter change re-renders only the widgets whose inputs changed.

## Commands

```bash
npm install
npm run sample-data   # public/data/costs.json; skill path from $FRONTEND_DASHBOARDS_SKILL, default ~/.kiro/skills/frontend-dashboards
npm run dev           # http://localhost:5173
npm run build         # tsc --noEmit && vite build -> dist/ (relative base: host under any path)
npm run typecheck
```

The kit pins direct dependencies exactly and deliberately ships **no** `package-lock.json`: the
lockfile belongs to the project the kit is copied into. Commit the one `npm install` generates there.

## Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Every action re-renders every widget | Inline object selector, or unstable fallback | Narrow selectors, `EMPTY` constants |
| Dev build sluggish after data loads | Immutable/serializable checks walking rows | `ignoredPaths` (already set) |
| Chart shows a series that was filtered out | `setOption` merge mode | `notMerge: true` (already set) |
| Chart doesn't follow theme | Colors hardcoded or tokens not memoized on theme | Read via `useChartTokens()` |
| Data fetched twice in dev | StrictMode double effect | Thunk `condition` (already set) |
| `Type 'string | undefined'` on array index | `noUncheckedIndexedAccess` | Handle the undefined (`?? fallback`), don't disable the flag |
| Bundle > 500 kB warning | ECharts | Register only used charts/components; it is split to its own chunk |
