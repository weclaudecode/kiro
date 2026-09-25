# Charts (ECharts 6)

## Choose the form from the question

| Question | Form | Notes |
|---|---|---|
| "How much, and is it up or down?" | KPI card + delta + sparkline | Not a chart. The number is the answer |
| "How did spend move over time?" | Line (1-3 series) or stacked bar (composition, daily) | Stacked area only when the total matters more than the parts |
| "What is it made of over time?" | Stacked bar by day, top 7 + Other | The kit's trend chart |
| "Who spends most?" | Horizontal bar, sorted, one color | Long category labels read better horizontally |
| "What changed most?" | Diverging horizontal bar (red = up, blue = down), signed labels | Top movers |
| "Share of total?" | Bar with % labels, or a share column in the table | Donut only for 2-4 parts that differ clearly |
| "Service x account intensity?" | Heatmap, single-hue sequential ramp | `--series-1` light to dark; add a visual map legend |
| "Actual vs budget?" | Bar + a `markLine` at the budget | Not dual axis |
| Two measures on different scales | Two charts, or index both to 100 | **Never a dual y-axis** |

## Palette rules (validated, do not improvise)

- Categorical slots `--series-1..8` come in a fixed order, CVD-checked in both themes. Assign by
  entity rank over the **whole dataset**, once at load (`colorSlot`). A filter must not repaint survivors.
- Use at most 7 named series plus `--series-other` (gray). Never generate a 9th hue.
- Scatter, bubble, and small multiples, where every pair of series is compared: cap at **3** series.
- Sequential (magnitude): one hue, light to dark. Diverging: two poles (blue and red) with a gray midpoint.
- Status colors mean state, never "series 4".
- Text (labels, legends, values) uses ink tokens, never the series color.
- If you change the palette, re-validate it for color-vision deficiency. The palette in
  `tokens.css` is the validated dataviz reference palette. Do not reorder it casually, because the
  order is part of what makes it safe.

## The wrapper is the only entry point

Vanilla: `createChart(el, { label, onClick }).render((tokens) => option)`.
React: `<EChart option={option} label="..." onClick={...} />` with `option` built by a pure function
in `src/charts/options.ts` and memoized on `[tokens, data, formatters]`.

The wrapper handles `init`, `ResizeObserver`, theme re-render, `role="img"` + `aria-label`, and
`dispose`. Feature code never calls `echarts.init`.

Every option spreads `baseOption(t)` / `base(t)`, which provides a transparent background, token
text colors, `aria.enabled` (ECharts generates a text description), a reduced-motion-aware
animation, and a token-styled tooltip with `confine: true`.

## Option patterns that matter

```js
// Recessive axes: gridlines in --grid, no axis line on value axis, muted labels.
yAxis: valueAxis(t, compactMoney),
xAxis: categoryAxis(t, dates, { axisLabel: { color: t.muted, hideOverlap: true, formatter: shortDate } }),

// Tooltip: axis-triggered for time series, sorted, currency-formatted.
tooltip: { ...base.tooltip, trigger: "axis", axisPointer: { type: "shadow" }, order: "valueDesc", valueFormatter: money },

// Stacked bars: surface-colored 1px border = spacer between segments (drop it past ~60 bars).
itemStyle: { borderColor: t.surface, borderWidth: 1 },

// End labels on horizontal bars need room: grid.right >= 56 or they clip on phones.
grid: { left: 16, right: 56, top: 8, bottom: 8, containLabel: true },

// Long AWS names: short label on the axis/legend, full name stays in tooltip/table.
legend: { formatter: awsServiceLabel }, yAxis: { axisLabel: { formatter: awsServiceLabel } },

// Cross-filter from a click.
onClick: (p) => store.dispatch({ type: "dimension/toggle", dimension: "accounts", value: p.name }),
```

- Round values before handing them to ECharts (`Math.round(x * 100) / 100`). Tooltips otherwise show float noise.
- Use `setOption(option, { notMerge: true })`. The option is the full truth. Merging leaves stale
  series behind after a filter removes one.
- De-emphasize unselected bars with `opacity: 0.35` instead of removing them, so the reader keeps context.
- Legend: always present for 2 or more series, `type: "scroll"` when names are long. No legend for a single series (the title names it).
- Selective direct labels: end-of-bar values, yes. A number on every point, no.

## Loading and upgrading ECharts

- **Vanilla:** a pinned jsDelivr URL with SRI. To upgrade:
  ```bash
  V=6.1.0
  curl -sSL "https://cdn.jsdelivr.net/npm/echarts@$V/dist/echarts.min.js" -o /tmp/e.js
  echo "sha384-$(openssl dgst -sha384 -binary /tmp/e.js | openssl base64 -A)"
  ```
  Update both `src` and `integrity`. Offline or air-gapped: vendor the file next to `index.html` and
  keep the `integrity` attribute.
- **React:** exact version in `package.json`. Tree-shake with
  `echarts.use([BarChart, GridComponent, ...])` in `EChart.tsx` and register only what you use. Each
  chart type adds bundle weight. ECharts gets its own chunk in `vite.config.ts` so app deploys don't
  bust its cache.
- If ECharts fails to load, the vanilla wrapper renders an error state in each chart slot. KPIs and
  the table still work.

## Anti-patterns (if your chart matches one, change it)

Dual axis; rainbow ramps; a hue at the diverging midpoint; recolor-on-filter; a 9th generated hue;
pie of 12 services; 3D anything; a one-bar bar chart (use a KPI); axis labels overlapping (use
`hideOverlap`, short labels, or rotate at most 30 degrees); a chart without a visible title; a
tooltip showing `6025.000000000001`.
