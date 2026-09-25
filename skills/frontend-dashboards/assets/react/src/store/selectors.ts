// Memoized selectors: (dataset, filters) -> everything the widgets render.
// Each widget subscribes to the narrowest selector it needs, so changing groupBy doesn't recompute the trend.
import { createSelector } from "@reduxjs/toolkit";
import { addDays, daysBetween, parseDay } from "../lib/format";
import { filterRows, previousRange, resolveRange, sumBy, total } from "../lib/data";
import type { CostRow, Dimension, GroupedRow } from "../lib/types";
import type { RootState } from "./index";

export const selectStatus = (s: RootState) => s.data.status;
export const selectError = (s: RootState) => s.data.error;
export const selectDataset = (s: RootState) => s.data.dataset;
export const selectFilters = (s: RootState) => s.filters;
export const selectGroupBy = (s: RootState) => s.filters.groupBy;
const selectRange = (s: RootState) => s.filters.range;
const selectAccounts = (s: RootState) => s.filters.accounts;
const selectEnvironments = (s: RootState) => s.filters.environments;
const selectServices = (s: RootState) => s.filters.services;
const selectRegions = (s: RootState) => s.filters.regions;

// Stable object of dimension filters: only changes when one of the four arrays changes (not on groupBy).
const selectDims = createSelector(
  [selectAccounts, selectEnvironments, selectServices, selectRegions],
  (accounts, environments, services, regions): Record<Dimension, string[]> => ({ accounts, environments, services, regions }),
);

export const selectPeriod = createSelector([selectDataset, selectRange], (ds, preset) => {
  if (!ds) return null;
  const range = resolveRange(preset, ds.meta);
  const prev = previousRange(range);
  return { range, prev, hasPrev: prev.start >= ds.meta.start, days: daysBetween(range.start, range.end) };
});

const EMPTY: CostRow[] = [];

export const selectRows = createSelector([selectDataset, selectDims, selectPeriod], (ds, dims, p) =>
  ds && p ? filterRows(ds.rows, dims, p.range) : EMPTY,
);

export const selectPrevRows = createSelector([selectDataset, selectDims, selectPeriod], (ds, dims, p) =>
  ds && p && p.hasPrev ? filterRows(ds.rows, dims, p.prev) : null,
);

export const selectKpis = createSelector([selectDataset, selectDims, selectPeriod, selectRows, selectPrevRows], (ds, dims, p, rows, prevRows) => {
  if (!ds || !p) return null;
  const spend = total(rows);
  // Month-end forecast: month-to-date actuals + trailing 7-day run rate for the remaining days.
  const end = ds.meta.end;
  const mtd = total(filterRows(ds.rows, dims, { start: `${end.slice(0, 7)}-01`, end }));
  const last7 = total(filterRows(ds.rows, dims, { start: addDays(end, -6), end }));
  const d = parseDay(end);
  const daysInMonth = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  return {
    spend,
    prevSpend: prevRows ? total(prevRows) : null,
    avgDaily: p.days ? spend / p.days : 0,
    forecast: mtd + (last7 / 7) * (daysInMonth - d.getUTCDate()),
  };
});

export interface TrendSeries {
  name: string;
  slot: number | null;
  values: number[];
}

export const selectTrend = createSelector([selectDataset, selectPeriod, selectRows], (ds, p, rows) => {
  if (!ds || !p) return { dates: [] as string[], series: [] as TrendSeries[], daily: [] as number[] };
  const dates: string[] = [];
  for (let d = p.range.start; d <= p.range.end; d = addDays(d, 1)) dates.push(d);
  const idx = new Map(dates.map((d, i) => [d, i]));
  const map = new Map<string, TrendSeries>();
  for (const r of rows) {
    const slot = ds.colorSlot[r.service] ?? null;
    const name = slot ? r.service : "Other";
    let s = map.get(name);
    if (!s) map.set(name, (s = { name, slot, values: new Array<number>(dates.length).fill(0) }));
    s.values[idx.get(r.date)!]! += r.cost;
  }
  const series = [...map.values()].sort((a, b) => (a.slot ?? 99) - (b.slot ?? 99));
  const daily = dates.map((_, i) => series.reduce((sum, s) => sum + s.values[i]!, 0));
  return { dates, series, daily };
});

export const selectGrouped = createSelector([selectRows, selectPrevRows, selectGroupBy], (rows, prevRows, groupBy): GroupedRow[] => {
  const spend = total(rows);
  const cur = sumBy(rows, groupBy);
  const prev = prevRows ? sumBy(prevRows, groupBy) : new Map<string, number>();
  return [...new Set([...cur.keys(), ...prev.keys()])].map((name) => {
    const cost = cur.get(name) ?? 0;
    const prior = prevRows ? (prev.get(name) ?? 0) : null;
    return {
      name,
      cost,
      share: spend ? cost / spend : 0,
      prior,
      change: prior === null ? null : cost - prior,
      changePct: prior ? (cost - prior) / prior : null,
    };
  });
});

export const selectTop = createSelector([selectGrouped], (grouped) =>
  grouped.filter((g) => g.cost > 0).reduce<GroupedRow | null>((best, g) => (!best || g.cost > best.cost ? g : best), null),
);

export const selectByAccount = createSelector([selectRows], (rows) => [...sumBy(rows, "accountName").entries()].sort((a, b) => b[1] - a[1]));

export const selectMovers = createSelector([selectRows, selectPrevRows], (rows, prevRows) => {
  if (!prevRows) return [];
  const now = sumBy(rows, "service");
  const before = sumBy(prevRows, "service");
  return [...new Set([...now.keys(), ...before.keys()])]
    .map((name) => ({ name, change: (now.get(name) ?? 0) - (before.get(name) ?? 0) }))
    .sort((a, b) => Math.abs(b.change) - Math.abs(a.change))
    .slice(0, 8);
});
