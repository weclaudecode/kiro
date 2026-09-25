// What the user chose. Nothing derived lives here - selectors compute totals/series/rows.
import { createSlice, type PayloadAction } from "@reduxjs/toolkit";
import type { Dimension, GroupBy, RangePreset } from "../lib/types";

export const RANGE_PRESETS: RangePreset[] = ["7d", "30d", "90d", "mtd", "prev-month", "all"];
export const GROUP_BYS: GroupBy[] = ["service", "accountName", "environment", "region"];
export const DIMENSIONS: Dimension[] = ["accounts", "environments", "services", "regions"];

export interface FiltersState {
  range: RangePreset;
  accounts: string[]; // empty = all
  environments: string[];
  services: string[];
  regions: string[];
  groupBy: GroupBy;
}

export const initialFilters: FiltersState = {
  range: "30d",
  accounts: [],
  environments: [],
  services: [],
  regions: [],
  groupBy: "service",
};

const filtersSlice = createSlice({
  name: "filters",
  initialState: initialFilters,
  reducers: {
    rangeSet(state, action: PayloadAction<RangePreset>) {
      state.range = action.payload;
    },
    dimensionSet(state, action: PayloadAction<{ dimension: Dimension; values: string[] }>) {
      state[action.payload.dimension] = action.payload.values;
    },
    dimensionToggled(state, action: PayloadAction<{ dimension: Dimension; value: string }>) {
      const { dimension, value } = action.payload;
      const list = state[dimension];
      const i = list.indexOf(value);
      if (i >= 0) list.splice(i, 1);
      else list.push(value);
    },
    groupBySet(state, action: PayloadAction<GroupBy>) {
      state.groupBy = action.payload;
    },
    filtersReset(state) {
      return { ...initialFilters, groupBy: state.groupBy };
    },
    hydrated(_state, action: PayloadAction<FiltersState>) {
      return action.payload;
    },
  },
});

export const { rangeSet, dimensionSet, dimensionToggled, groupBySet, filtersReset, hydrated } = filtersSlice.actions;
export default filtersSlice.reducer;

// ---- URL hash <-> filters (shareable links, survives reload) ----

export function filtersFromHash(hash: string): FiltersState {
  const p = new URLSearchParams(hash.replace(/^#/, ""));
  const range = p.get("range") as RangePreset | null;
  const groupBy = p.get("groupBy") as GroupBy | null;
  const out: FiltersState = {
    ...initialFilters,
    range: range && RANGE_PRESETS.includes(range) ? range : initialFilters.range,
    groupBy: groupBy && GROUP_BYS.includes(groupBy) ? groupBy : initialFilters.groupBy,
  };
  for (const dim of DIMENSIONS) out[dim] = (p.get(dim) ?? "").split(",").filter(Boolean);
  return out;
}

export function hashFromFilters(f: FiltersState): string {
  const p = new URLSearchParams();
  if (f.range !== initialFilters.range) p.set("range", f.range);
  if (f.groupBy !== initialFilters.groupBy) p.set("groupBy", f.groupBy);
  for (const dim of DIMENSIONS) if (f[dim].length) p.set(dim, f[dim].join(","));
  const s = p.toString();
  return s ? `#${s}` : "";
}
