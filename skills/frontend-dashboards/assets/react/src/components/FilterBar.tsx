// One filter row above everything it filters. Every interaction dispatches; no local filter state.
import { useEffect, useRef } from "react";
import { useAppDispatch, useAppSelector } from "../store/hooks";
import { dimensionSet, dimensionToggled, filtersReset, rangeSet } from "../store/filtersSlice";
import { selectFilters } from "../store/selectors";
import type { Dimension, RangePreset } from "../lib/types";

const RANGE_LABELS: Record<RangePreset, string> = {
  "7d": "7D",
  "30d": "30D",
  "90d": "90D",
  mtd: "MTD",
  "prev-month": "Last month",
  all: "All",
};

interface Props {
  dimensions: { key: Dimension; label: string; options: string[] }[];
}

export function FilterBar({ dimensions }: Props) {
  const dispatch = useAppDispatch();
  const filters = useAppSelector(selectFilters);

  return (
    <section className="filter-bar" aria-label="Filters">
      <div className="field">
        <span className="field-label" id="range-label">
          Period
        </span>
        <div className="segmented" role="group" aria-labelledby="range-label">
          {(Object.keys(RANGE_LABELS) as RangePreset[]).map((k) => (
            <button key={k} type="button" aria-pressed={filters.range === k} onClick={() => dispatch(rangeSet(k))}>
              {RANGE_LABELS[k]}
            </button>
          ))}
        </div>
      </div>
      {dimensions.map((d) => (
        <MultiSelect
          key={d.key}
          label={d.label}
          options={d.options}
          selected={filters[d.key]}
          onToggle={(value) => dispatch(dimensionToggled({ dimension: d.key, value }))}
          onClear={() => dispatch(dimensionSet({ dimension: d.key, values: [] }))}
        />
      ))}
      <div className="filter-actions">
        <button type="button" className="btn" onClick={() => dispatch(filtersReset())}>
          Reset filters
        </button>
      </div>
    </section>
  );
}

interface MultiSelectProps {
  label: string;
  options: string[];
  selected: string[];
  onToggle: (value: string) => void;
  onClear: () => void;
}

// Native <details> popover with checkboxes: keyboard accessible without a library. Empty selection = all.
function MultiSelect({ label, options, selected, onToggle, onClear }: MultiSelectProps) {
  const ref = useRef<HTMLDetailsElement>(null);
  const labelId = `ms-${label.toLowerCase().replace(/\W+/g, "-")}`;

  useEffect(() => {
    const close = (e: MouseEvent) => {
      if (ref.current?.open && !ref.current.contains(e.target as Node)) ref.current.open = false;
    };
    document.addEventListener("click", close);
    return () => document.removeEventListener("click", close);
  }, []);

  const summary = selected.length === 0 ? "All" : selected.length === 1 ? selected[0] : `${selected.length} selected`;

  return (
    <div className="field">
      <span className="field-label" id={labelId}>
        {label}
      </span>
      <details
        ref={ref}
        className="multiselect"
        onKeyDown={(e) => {
          if (e.key === "Escape" && ref.current?.open) {
            ref.current.open = false;
            ref.current.querySelector("summary")?.focus();
          }
        }}
      >
        <summary aria-labelledby={labelId}>
          <span>{summary}</span>
        </summary>
        <div className="multiselect-panel" role="group" aria-labelledby={labelId}>
          <div className="panel-actions">
            <button type="button" className="link-btn" onClick={onClear}>
              Select all
            </button>
            <button type="button" className="link-btn" onClick={onClear}>
              Clear
            </button>
          </div>
          {options.map((o) => (
            <label key={o}>
              <input type="checkbox" checked={selected.includes(o)} onChange={() => onToggle(o)} /> {o}
            </label>
          ))}
        </div>
      </details>
    </div>
  );
}
