// Pure option builders: (view data, tokens, formatters) -> ECharts option. Easy to unit test, no DOM.
import type { EChartsCoreOption } from "echarts/core";
import { awsServiceLabel, shortDate } from "../lib/format";
import type { TrendSeries } from "../store/selectors";
import type { ChartTokens } from "./theme";

type Fmt = (v: number) => string;

const reducedMotion = () => typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;
const round2 = (x: number) => Math.round(x * 100) / 100;

export function base(t: ChartTokens) {
  return {
    backgroundColor: "transparent",
    textStyle: { fontFamily: t.font, color: t.textSecondary },
    animationDuration: reducedMotion() ? 0 : 300,
    aria: { enabled: true },
    grid: { left: 8, right: 16, top: 16, bottom: 8, containLabel: true },
    tooltip: {
      backgroundColor: t.surface,
      borderColor: t.border,
      borderWidth: 1,
      textStyle: { color: t.text, fontSize: 12 },
      extraCssText: "box-shadow:0 8px 24px rgba(0,0,0,.12);border-radius:6px;",
      confine: true,
    },
  };
}

const valueAxis = (t: ChartTokens, formatter: Fmt) => ({
  type: "value",
  axisLabel: { color: t.muted, formatter, hideOverlap: true },
  splitLine: { lineStyle: { color: t.grid } },
  axisLine: { show: false },
  axisTick: { show: false },
});

const categoryAxis = (t: ChartTokens, data: string[], formatter?: (v: string) => string) => ({
  type: "category",
  data,
  axisLabel: { color: t.muted, hideOverlap: true, formatter },
  axisLine: { lineStyle: { color: t.axis } },
  axisTick: { show: false },
});

export function trendOption(t: ChartTokens, dates: string[], series: TrendSeries[], money: Fmt, compact: Fmt): EChartsCoreOption {
  const b = base(t);
  return {
    ...b,
    grid: { ...b.grid, top: 56 },
    // Color follows the entity: slot is frozen per service at load, so filtering never repaints survivors.
    color: series.map((s) => (s.slot ? (t.series[s.slot - 1] ?? t.other) : t.other)),
    legend: {
      type: "scroll",
      top: 0,
      icon: "roundRect",
      itemWidth: 10,
      itemHeight: 10,
      textStyle: { color: t.textSecondary },
      pageTextStyle: { color: t.muted },
      formatter: awsServiceLabel,
    },
    tooltip: { ...b.tooltip, trigger: "axis", axisPointer: { type: "shadow" }, order: "valueDesc", valueFormatter: (v: number) => money(v) },
    xAxis: categoryAxis(t, dates, shortDate),
    yAxis: valueAxis(t, compact),
    series: series.map((s) => ({
      name: s.name,
      type: "bar",
      stack: "spend",
      data: s.values.map(round2),
      barCategoryGap: "20%",
      itemStyle: { borderColor: t.surface, borderWidth: dates.length > 60 ? 0 : 1 },
      emphasis: { focus: "series" },
    })),
  };
}

export function accountOption(t: ChartTokens, byAccount: [string, number][], selected: string[], money: Fmt, compact: Fmt): EChartsCoreOption {
  const b = base(t);
  const rows = [...byAccount].reverse(); // horizontal bars: largest on top
  return {
    ...b,
    grid: { ...b.grid, left: 16, right: 56, top: 8 },
    tooltip: { ...b.tooltip, trigger: "item", valueFormatter: (v: number) => money(v) },
    xAxis: valueAxis(t, compact),
    yAxis: categoryAxis(t, rows.map(([n]) => n)),
    series: [
      {
        type: "bar",
        name: "Spend",
        cursor: "pointer",
        barMaxWidth: 28,
        itemStyle: { color: t.series[0], borderRadius: [0, 4, 4, 0] },
        label: { show: true, position: "right", color: t.textSecondary, formatter: (p: { value: number }) => compact(p.value) },
        data: rows.map(([n, c]) => ({ value: round2(c), itemStyle: { opacity: selected.length && !selected.includes(n) ? 0.35 : 1 } })),
      },
    ],
  };
}

export function moversOption(t: ChartTokens, movers: { name: string; change: number }[], money: Fmt, compact: Fmt): EChartsCoreOption {
  const b = base(t);
  const rows = [...movers].reverse();
  const increase = t.series[7] ?? t.other; // diverging pair: red = spend rose, blue = spend fell
  const decrease = t.series[0] ?? t.other;
  return {
    ...b,
    grid: { ...b.grid, left: 16, right: 56, top: 8 },
    tooltip: { ...b.tooltip, trigger: "item", valueFormatter: (v: number) => `${v > 0 ? "+" : ""}${money(v)}` },
    xAxis: valueAxis(t, compact),
    yAxis: categoryAxis(t, rows.map((m) => m.name), awsServiceLabel),
    series: [
      {
        type: "bar",
        name: "Change",
        barMaxWidth: 22,
        // Signed labels so direction never relies on color alone.
        label: {
          show: true,
          position: "right",
          color: t.textSecondary,
          formatter: (p: { value: number }) => `${p.value > 0 ? "+" : "−"}${compact(Math.abs(p.value))}`,
        },
        data: rows.map((m) => ({
          value: round2(m.change),
          itemStyle: { color: m.change > 0 ? increase : decrease, borderRadius: m.change > 0 ? [0, 4, 4, 0] : [4, 0, 0, 4] },
        })),
      },
    ],
  };
}
