// Data loading, validation and selectors (pure functions of data + state).
import { addDays, daysBetween, parseDay, toDay } from "./format.js";

const REQUIRED = ["date", "accountId", "accountName", "environment", "service", "region", "cost"];
const MAX_SERIES = 7; // slots 1-7 are named series; slot 8+ folds into "Other"

export class DataError extends Error {}

export async function loadCostData(url) {
  let res;
  try {
    res = await fetch(url, { cache: "no-cache" });
  } catch (err) {
    throw new DataError(
      location.protocol === "file:"
        ? "Browsers block fetch() from file:// pages. Serve the folder: python3 -m http.server 8000"
        : `Network error loading ${url}: ${err.message}`,
    );
  }
  if (res.status === 404) throw new DataError(`No data at ${url}. Generate it: python3 scripts/gen_sample_costs.py -o ${url}`);
  if (!res.ok) throw new DataError(`Loading ${url} failed: HTTP ${res.status}`);
  const doc = await res.json();
  return prepare(doc);
}

// Validate once at the boundary, then trust the shape everywhere else.
export function prepare(doc) {
  if (!doc || doc.meta?.schemaVersion !== 1 || !Array.isArray(doc.rows)) {
    throw new DataError("Unexpected data shape: need { meta: { schemaVersion: 1 }, rows: [] }");
  }
  const bad = doc.rows.find((r) => REQUIRED.some((k) => r[k] === undefined) || typeof r.cost !== "number");
  if (bad) throw new DataError(`Row missing a required field or with non-numeric cost: ${JSON.stringify(bad)}`);

  const rows = doc.rows;
  if (!rows.length) throw new DataError("The data file has no rows. Check the export's date range and filters.");
  const dims = {
    accounts: uniqueSorted(rows, "accountName"),
    environments: uniqueSorted(rows, "environment"),
    services: uniqueSorted(rows, "service"),
    regions: uniqueSorted(rows, "region"),
  };
  // Color follows the entity, never its rank in the current filter: rank services once over the
  // whole dataset and freeze the mapping. Filtering never repaints a survivor.
  const serviceRank = rankBy(rows, "service");
  const colorSlot = new Map(serviceRank.map((name, i) => [name, i < MAX_SERIES ? i + 1 : null]));
  const start = rows.reduce((m, r) => (r.date < m ? r.date : m), rows[0]?.date ?? "");
  const end = rows.reduce((m, r) => (r.date > m ? r.date : m), rows[0]?.date ?? "");
  return { meta: { ...doc.meta, start, end }, rows, dims, colorSlot };
}

function uniqueSorted(rows, key) {
  return [...new Set(rows.map((r) => r[key]))].sort((a, b) => String(a).localeCompare(String(b)));
}

function rankBy(rows, key) {
  return [...sumBy(rows, key).entries()].sort((a, b) => b[1] - a[1]).map(([k]) => k);
}

export function sumBy(rows, key) {
  const out = new Map();
  for (const r of rows) out.set(r[key], (out.get(r[key]) ?? 0) + r.cost);
  return out;
}

export function total(rows) {
  let t = 0;
  for (const r of rows) t += r.cost;
  return t;
}

// ---- Date range resolution: relative to the DATA's last day, not today (the file is a snapshot) ----

export function resolveRange(preset, meta) {
  const end = meta.end;
  switch (preset) {
    case "7d":
      return { start: maxDay(addDays(end, -6), meta.start), end };
    case "30d":
      return { start: maxDay(addDays(end, -29), meta.start), end };
    case "90d":
      return { start: maxDay(addDays(end, -89), meta.start), end };
    case "mtd":
      return { start: maxDay(`${end.slice(0, 7)}-01`, meta.start), end };
    case "prev-month": {
      const firstOfMonth = parseDay(`${end.slice(0, 7)}-01`);
      const last = new Date(firstOfMonth);
      last.setUTCDate(0);
      return { start: maxDay(`${toDay(last).slice(0, 7)}-01`, meta.start), end: toDay(last) };
    }
    default:
      return { start: meta.start, end };
  }
}

// Equal-length window immediately before the range, for "vs previous period".
export function previousRange(range) {
  const len = daysBetween(range.start, range.end);
  return { start: addDays(range.start, -len), end: addDays(range.start, -1) };
}

function maxDay(a, b) {
  return a > b ? a : b;
}

// ---- Selectors ----

const DIM_FIELD = { accounts: "accountName", environments: "environment", services: "service", regions: "region" };

function matchesDims(state) {
  const checks = Object.entries(DIM_FIELD)
    .filter(([dim]) => state[dim].length)
    .map(([dim, field]) => [field, new Set(state[dim])]);
  return (r) => checks.every(([field, set]) => set.has(r[field]));
}

export function filterRows(data, state, range) {
  const match = matchesDims(state);
  return data.rows.filter((r) => r.date >= range.start && r.date <= range.end && match(r));
}

// Memoize on input identity: the reducer returns a new object only when state changes.
export function memoize(fn) {
  let lastArgs = [];
  let lastResult;
  return (...args) => {
    if (args.length === lastArgs.length && args.every((a, i) => a === lastArgs[i])) return lastResult;
    lastArgs = args;
    lastResult = fn(...args);
    return lastResult;
  };
}

export const selectView = memoize((data, state) => {
  const range = resolveRange(state.range, data.meta);
  const prevRange = previousRange(range);
  const rows = filterRows(data, state, range);
  const prevRows = prevRange.start >= data.meta.start ? filterRows(data, state, prevRange) : null;
  const days = daysBetween(range.start, range.end);
  const spend = total(rows);
  const prevSpend = prevRows ? total(prevRows) : null;

  // Daily trend, stacked by service (top N by the frozen rank, rest = Other)
  const dates = [];
  for (let d = range.start; d <= range.end; d = addDays(d, 1)) dates.push(d);
  const dateIndex = new Map(dates.map((d, i) => [d, i]));
  const seriesMap = new Map();
  for (const r of rows) {
    const slot = data.colorSlot.get(r.service);
    const name = slot ? r.service : "Other";
    if (!seriesMap.has(name)) seriesMap.set(name, { name, slot, values: new Array(dates.length).fill(0) });
    seriesMap.get(name).values[dateIndex.get(r.date)] += r.cost;
  }
  const trend = {
    dates,
    series: [...seriesMap.values()].sort((a, b) => (a.slot ?? 99) - (b.slot ?? 99)),
  };
  const daily = dates.map((_, i) => trend.series.reduce((s, x) => s + x.values[i], 0));

  // Month-end forecast: month-to-date actuals + trailing 7-day run rate for the remaining days.
  const monthStart = `${data.meta.end.slice(0, 7)}-01`;
  const mtdRows = filterRows(data, state, { start: monthStart, end: data.meta.end });
  const last7 = filterRows(data, state, { start: addDays(data.meta.end, -6), end: data.meta.end });
  const d = parseDay(data.meta.end);
  const daysInMonth = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  const remaining = daysInMonth - d.getUTCDate();
  const forecast = total(mtdRows) + (total(last7) / 7) * remaining;

  // Grouped table rows with previous-period comparison
  const cur = sumBy(rows, state.groupBy);
  const prev = prevRows ? sumBy(prevRows, state.groupBy) : new Map();
  const keys = new Set([...cur.keys(), ...prev.keys()]);
  const grouped = [...keys].map((name) => {
    const cost = cur.get(name) ?? 0;
    const prior = prevRows ? prev.get(name) ?? 0 : null;
    return {
      name,
      cost,
      share: spend ? cost / spend : 0,
      prior,
      change: prior === null ? null : cost - prior,
      changePct: prior ? (cost - prior) / prior : null,
    };
  });

  const byAccount = [...sumBy(rows, "accountName").entries()].sort((a, b) => b[1] - a[1]);
  let movers = [];
  if (prevRows) {
    const now = sumBy(rows, "service");
    const before = sumBy(prevRows, "service");
    movers = [...new Set([...now.keys(), ...before.keys()])]
      .map((name) => ({ name, change: (now.get(name) ?? 0) - (before.get(name) ?? 0) }))
      .sort((a, b) => Math.abs(b.change) - Math.abs(a.change))
      .slice(0, 8);
  }

  const top = grouped.filter((g) => g.cost > 0).sort((a, b) => b.cost - a.cost)[0];

  return { range, prevRange, rows, days, spend, prevSpend, trend, daily, forecast, grouped, byAccount, movers, top, rowCount: rows.length };
});
