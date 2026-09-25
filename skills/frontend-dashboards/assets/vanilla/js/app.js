// Wiring: load data -> create store -> mount components -> render on every state change.
// Feature code lives here; generic components live in components/. Keep this file declarative.
import { awsServiceLabel, currency, delta, esc, longDate, percent, shortDate } from "./format.js";
import { createStore, initialState, reducer, stateFromHash, syncToUrl } from "./store.js";
import { DataError, loadCostData, selectView } from "./data.js";
import { baseOption, categoryAxis, createChart, valueAxis } from "./components/chart.js";
import { createTable } from "./components/table.js";
import { renderKpi, renderKpiSkeleton } from "./components/kpi.js";
import { createFilterBar } from "./components/filters.js";

const DATA_URL = "data/costs.json";
const GROUP_LABEL = { service: "service", accountName: "account", environment: "environment", region: "region" };
const GROUP_DIM = { service: "services", accountName: "accounts", environment: "environments", region: "regions" };
const $ = (id) => document.getElementById(id);
const round = (v, dp) => (v == null ? null : Number(v.toFixed(dp))); // CSV: sums carry binary float noise
const KPI_IDS = ["kpi-spend", "kpi-daily", "kpi-forecast", "kpi-top"];

setupThemeToggle();
KPI_IDS.forEach((id) => renderKpiSkeleton($(id)));

try {
  const data = await loadCostData(DATA_URL);
  mount(data);
} catch (err) {
  showError(err);
}

function mount(data) {
  const cur = data.meta.currency ?? "USD";
  const money = (v) => currency(v, cur);
  const cents = (v) => currency(v, cur, { decimals: 2 }); // tables: fixed decimals so columns align
  const compact = (v) => currency(v, cur, { compact: true });

  $("data-subtitle").textContent =
    `${data.meta.metric ?? "Cost"} · ${cur} · data ${longDate(data.meta.start)} – ${longDate(data.meta.end)}` +
    (data.meta.source ? ` · source: ${data.meta.source}` : "");

  const store = createStore(reducer, { ...initialState, ...stateFromHash() });
  syncToUrl(store);

  createFilterBar($("filters"), store, {
    dimensions: [
      { key: "accounts", label: "Account", options: data.dims.accounts },
      { key: "environments", label: "Environment", options: data.dims.environments },
      { key: "services", label: "Service", options: data.dims.services },
      { key: "regions", label: "Region", options: data.dims.regions },
    ],
  });

  const trendChart = createChart($("chart-trend"), { label: "Stacked bar chart of daily spend by service" });
  const accountChart = createChart($("chart-accounts"), {
    label: "Bar chart of spend by account",
    onClick: (p) => store.dispatch({ type: "dimension/toggle", dimension: "accounts", value: p.name }),
  });
  const moversChart = createChart($("chart-movers"), { label: "Diverging bar chart of change in spend by service" });

  const table = createTable($("breakdown-table"), {
    caption: "Cost breakdown with previous-period comparison",
    searchKeys: ["name"],
    defaultSort: { key: "cost", dir: "desc" },
    pageSize: 15,
    filename: `aws-cost-breakdown-${data.meta.end}.csv`,
    onRowClick: (row) => {
      const dim = GROUP_DIM[store.getState().groupBy];
      store.dispatch({ type: "dimension/toggle", dimension: dim, value: row.name });
    },
    columns: [
      { key: "name", label: "Name" },
      { key: "cost", label: "Cost", numeric: true, total: true, render: (v) => esc(cents(v)), csv: (v) => round(v, 2) },
      {
        key: "share",
        label: "Share",
        numeric: true,
        csv: (v) => round(v, 4),
        render: (v) =>
          `<span class="bar-cell"><span class="bar" style="width:${(v * 100).toFixed(1)}%"></span>${esc(percent(v))}</span>`,
      },
      { key: "prior", label: "Prev. period", numeric: true, total: true, render: (v) => (v == null ? '<span class="muted">n/a</span>' : esc(cents(v))), csv: (v) => round(v, 2) },
      {
        key: "change",
        label: "Change",
        numeric: true,
        total: true,
        csv: (v) => round(v, 2),
        render: (v) => (v == null ? '<span class="muted">n/a</span>' : deltaCell(v, cents)),
      },
      {
        key: "changePct",
        label: "Change %",
        numeric: true,
        csv: (v) => round(v, 4),
        render: (v) => (v == null ? '<span class="muted">new</span>' : deltaCell(v, (x) => percent(x))),
      },
    ],
  });

  const groupSelect = $("group-by");
  groupSelect.addEventListener("change", () => store.dispatch({ type: "groupBy/set", value: groupSelect.value }));

  function render(state) {
    const v = selectView(data, state);
    groupSelect.value = state.groupBy;
    const period = `${shortDate(v.range.start)} – ${shortDate(v.range.end)}`;

    const d = v.prevSpend == null ? null : delta(v.spend, v.prevSpend, cur);
    renderKpi($("kpi-spend"), {
      label: "Total spend",
      value: money(v.spend),
      delta: d ?? undefined,
      foot: d ? `vs previous ${v.days} days` : period,
      spark: v.daily,
    });
    renderKpi($("kpi-daily"), {
      label: "Average daily spend",
      value: money(v.days ? v.spend / v.days : 0),
      foot: `over ${v.days} days · ${period}`,
    });
    renderKpi($("kpi-forecast"), {
      label: `Forecast, ${new Date(`${data.meta.end}T00:00:00Z`).toLocaleString(undefined, { month: "long", timeZone: "UTC" })}`,
      value: money(v.forecast),
      foot: "Month-to-date + trailing 7-day run rate",
    });
    renderKpi($("kpi-top"), {
      label: `Top ${GROUP_LABEL[state.groupBy]}`,
      value: v.top ? (state.groupBy === "service" ? awsServiceLabel(v.top.name) : v.top.name) : "—",
      title: v.top?.name,
      text: true,
      foot: v.top ? `${money(v.top.cost)} · ${percent(v.top.share)} of spend` : "No spend in range",
    });

    trendChart.render((t) => ({
      ...baseOption(t),
      grid: { left: 8, right: 16, top: 56, bottom: 8, containLabel: true },
      color: v.trend.series.map((s) => (s.slot ? t.series[s.slot - 1] : t.other)),
      legend: {
        type: "scroll",
        top: 0,
        textStyle: { color: t.textSecondary },
        pageTextStyle: { color: t.muted },
        itemWidth: 10,
        itemHeight: 10,
        icon: "roundRect",
        formatter: awsServiceLabel,
      },
      tooltip: {
        ...baseOption(t).tooltip,
        trigger: "axis",
        axisPointer: { type: "shadow" },
        order: "valueDesc",
        valueFormatter: (x) => money(x),
      },
      xAxis: categoryAxis(t, v.trend.dates, { axisLabel: { color: t.muted, hideOverlap: true, formatter: shortDate } }),
      yAxis: valueAxis(t, compact),
      series: v.trend.series.map((s) => ({
        name: s.name,
        type: "bar",
        stack: "spend",
        data: s.values.map((x) => Math.round(x * 100) / 100),
        barCategoryGap: "20%",
        itemStyle: { borderColor: t.surface, borderWidth: v.trend.dates.length > 60 ? 0 : 1 },
        emphasis: { focus: "series" },
      })),
    }));

    const accounts = [...v.byAccount].reverse(); // horizontal bars read top-down largest first
    accountChart.render((t) => ({
      ...baseOption(t),
      grid: { left: 16, right: 56, top: 8, bottom: 8, containLabel: true }, // room for end labels
      tooltip: { ...baseOption(t).tooltip, trigger: "item", valueFormatter: (x) => money(x) },
      xAxis: valueAxis(t, compact),
      yAxis: categoryAxis(t, accounts.map(([n]) => n)),
      series: [
        {
          type: "bar",
          name: "Spend",
          data: accounts.map(([n, c]) => ({
            value: Math.round(c * 100) / 100,
            itemStyle: { opacity: state.accounts.length && !state.accounts.includes(n) ? 0.35 : 1 },
          })),
          itemStyle: { color: t.series[0], borderRadius: [0, 4, 4, 0] },
          barMaxWidth: 28,
          label: { show: true, position: "right", color: t.textSecondary, formatter: (p) => compact(p.value) },
          cursor: "pointer",
        },
      ],
    }));

    $("movers-subtitle").textContent = v.prevSpend == null
      ? "No previous period in the data for this range"
      : `Change vs ${shortDate(v.prevRange.start)} – ${shortDate(v.prevRange.end)}, by service`;
    const movers = [...v.movers].reverse();
    moversChart.render((t) => ({
      ...baseOption(t),
      grid: { left: 16, right: 56, top: 8, bottom: 8, containLabel: true },
      tooltip: { ...baseOption(t).tooltip, trigger: "item", valueFormatter: (x) => `${x > 0 ? "+" : ""}${money(x)}` },
      xAxis: valueAxis(t, compact),
      yAxis: categoryAxis(t, movers.map((m) => m.name), { axisLabel: { color: t.muted, formatter: awsServiceLabel } }),
      series: [
        {
          type: "bar",
          name: "Change",
          // Diverging: blue = spend fell, red = spend rose. Labels carry the sign so color is never alone.
          data: movers.map((m) => ({
            value: Math.round(m.change * 100) / 100,
            itemStyle: { color: m.change > 0 ? t.series[7] : t.series[0], borderRadius: m.change > 0 ? [0, 4, 4, 0] : [4, 0, 0, 4] },
          })),
          barMaxWidth: 22,
          label: {
            show: true,
            position: "right",
            color: t.textSecondary,
            formatter: (p) => `${p.value > 0 ? "+" : "−"}${compact(Math.abs(p.value))}`,
          },
        },
      ],
    }));

    table.setRows(v.grouped);
  }

  render(store.getState());
  store.subscribe(render);
}

function deltaCell(v, fmt) {
  const dir = Math.abs(v) < 1e-9 ? "flat" : v > 0 ? "up" : "down";
  const sign = v > 0 ? "+" : v < 0 ? "−" : "";
  return `<span class="delta" data-dir="${dir}">${sign}${esc(fmt(Math.abs(v)))}</span>`;
}

function showError(err) {
  console.error(err);
  $("data-subtitle").textContent = "Data unavailable";
  $("app").innerHTML = `
    <section class="card state" data-kind="error" role="alert">
      <h2>Could not load the dashboard data</h2>
      <p>${esc(err instanceof DataError ? err.message : "Unexpected error - see the browser console.")}</p>
    </section>`;
}

function setupThemeToggle() {
  const btn = $("theme-toggle");
  const current = () =>
    document.documentElement.dataset.theme ?? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const label = () => (btn.textContent = current() === "dark" ? "Light mode" : "Dark mode");
  label();
  btn.addEventListener("click", () => {
    const next = current() === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("theme", next);
    } catch {}
    label();
    document.dispatchEvent(new Event("themechange"));
  });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", label);
}
