// Data contract (schemaVersion 1) - see references/data-contract.md. Mirrors the vanilla track.

export interface CostRow {
  date: string; // YYYY-MM-DD, UTC day
  accountId: string;
  accountName: string;
  environment: string;
  service: string;
  region: string;
  cost: number;
}

export interface CostMeta {
  schemaVersion: 1;
  source?: string;
  metric?: string;
  currency?: string;
  granularity?: "DAILY";
  start: string;
  end: string;
  generatedAt?: string;
  notes?: string;
}

export interface CostDoc {
  meta: CostMeta;
  rows: CostRow[];
}

/** Validated, load-once dataset. Plain objects only (it lives in the Redux store). */
export interface Dataset {
  meta: CostMeta;
  rows: CostRow[];
  dims: Record<Dimension, string[]>;
  /** service -> categorical slot 1..7, or null for "Other". Frozen at load: color follows the entity. */
  colorSlot: Record<string, number | null>;
}

export type Dimension = "accounts" | "environments" | "services" | "regions";
export type RangePreset = "7d" | "30d" | "90d" | "mtd" | "prev-month" | "all";
export type GroupBy = "service" | "accountName" | "environment" | "region";

export interface DayRange {
  start: string;
  end: string;
}

export interface GroupedRow {
  name: string;
  cost: number;
  share: number;
  prior: number | null;
  change: number | null;
  changePct: number | null;
}
