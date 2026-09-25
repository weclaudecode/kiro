// Loading, validation at the boundary, and pure aggregation helpers.
import { addDays, daysBetween, parseDay, toDay } from "./format";
import type { CostDoc, CostMeta, CostRow, Dataset, DayRange, Dimension, RangePreset } from "./types";

const REQUIRED: (keyof CostRow)[] = ["date", "accountId", "accountName", "environment", "service", "region", "cost"];
const MAX_SERIES = 7;

export class DataError extends Error {}

export async function fetchCostDoc(url: string): Promise<CostDoc> {
  let res: Response;
  try {
    res = await fetch(url, { cache: "no-cache" });
  } catch (err) {
    throw new DataError(`Network error loading ${url}: ${(err as Error).message}`);
  }
  if (res.status === 404) throw new DataError(`No data at ${url}. Generate it: npm run sample-data`);
  if (!res.ok) throw new DataError(`Loading ${url} failed: HTTP ${res.status}`);
  return (await res.json()) as CostDoc;
}

/** Validate once, then trust the shape everywhere else. */
export function prepare(doc: unknown): Dataset {
  const d = doc as Partial<CostDoc> | null;
  if (!d || d.meta?.schemaVersion !== 1 || !Array.isArray(d.rows)) {
    throw new DataError("Unexpected data shape: need { meta: { schemaVersion: 1 }, rows: [] }");
  }
  const rows = d.rows;
  if (!rows.length) throw new DataError("The data file has no rows. Check the export's date range and filters.");
  const bad = rows.find((r) => REQUIRED.some((k) => r[k] === undefined) || typeof r.cost !== "number");
  if (bad) throw new DataError(`Row missing a required field or with non-numeric cost: ${JSON.stringify(bad)}`);

  const uniq = (key: keyof CostRow) => [...new Set(rows.map((r) => String(r[key])))].sort((a, b) => a.localeCompare(b));
  const rank = [...sumBy(rows, "service").entries()].sort((a, b) => b[1] - a[1]).map(([k]) => k);
  const colorSlot = Object.fromEntries(rank.map((name, i) => [name, i < MAX_SERIES ? i + 1 : null]));
  let start = rows[0]?.date ?? "";
  let end = start;
  for (const r of rows) {
    if (r.date < start) start = r.date;
    if (r.date > end) end = r.date;
  }
  const meta: CostMeta = { ...d.meta, start, end };
  return {
    meta,
    rows,
    dims: { accounts: uniq("accountName"), environments: uniq("environment"), services: uniq("service"), regions: uniq("region") },
    colorSlot,
  };
}

export function sumBy(rows: readonly CostRow[], key: keyof CostRow): Map<string, number> {
  const out = new Map<string, number>();
  for (const r of rows) {
    const k = String(r[key]);
    out.set(k, (out.get(k) ?? 0) + r.cost);
  }
  return out;
}

export function total(rows: readonly CostRow[]): number {
  let t = 0;
  for (const r of rows) t += r.cost;
  return t;
}

const maxDay = (a: string, b: string) => (a > b ? a : b);

/** Ranges resolve against the DATA's last day, not today - the file is a snapshot. */
export function resolveRange(preset: RangePreset, meta: CostMeta): DayRange {
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
      const last = parseDay(`${end.slice(0, 7)}-01`);
      last.setUTCDate(0);
      return { start: maxDay(`${toDay(last).slice(0, 7)}-01`, meta.start), end: toDay(last) };
    }
    case "all":
      return { start: meta.start, end };
  }
}

export function previousRange(range: DayRange): DayRange {
  const len = daysBetween(range.start, range.end);
  return { start: addDays(range.start, -len), end: addDays(range.start, -1) };
}

export const DIM_FIELD: Record<Dimension, keyof CostRow> = {
  accounts: "accountName",
  environments: "environment",
  services: "service",
  regions: "region",
};

export function filterRows(rows: readonly CostRow[], dims: Record<Dimension, string[]>, range: DayRange): CostRow[] {
  const checks = (Object.keys(DIM_FIELD) as Dimension[])
    .filter((dim) => dims[dim].length)
    .map((dim) => [DIM_FIELD[dim], new Set(dims[dim])] as const);
  return rows.filter((r) => r.date >= range.start && r.date <= range.end && checks.every(([f, set]) => set.has(String(r[f]))));
}
