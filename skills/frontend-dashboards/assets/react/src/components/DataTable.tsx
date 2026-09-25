// Generic data table: search, sort, pagination, totals row, CSV export.
// Sort/search/page are LOCAL component state (only this table cares) - not Redux.
// Dashboard-wide filters arrive already applied via `rows`.
import { useDeferredValue, useId, useMemo, useState, type ReactNode } from "react";
import { downloadCsv } from "../lib/csv";

export interface Column<T> {
  key: keyof T & string;
  label: string;
  numeric?: boolean;
  /** Show the column sum in the footer. */
  total?: boolean;
  render?: (value: T[keyof T], row: T | null) => ReactNode;
  /** Raw CSV value. Default: the field as-is. Round floats here (sums carry binary noise). */
  csv?: (row: T) => string | number | null;
}

interface Props<T> {
  rows: T[];
  /** Stable identity for React keys (not the array index - sorting would remount rows). */
  rowKey: (row: T) => string;
  columns: Column<T>[];
  searchKeys: (keyof T & string)[];
  defaultSort?: { key: keyof T & string; dir: "asc" | "desc" };
  pageSize?: number;
  filename: string;
  caption: string;
  onRowClick?: (row: T) => void;
}

type Sort<T> = { key: keyof T & string; dir: "asc" | "desc" } | null;

export function DataTable<T extends object>({
  rows,
  rowKey,
  columns,
  searchKeys,
  defaultSort,
  pageSize = 25,
  filename,
  caption,
  onRowClick,
}: Props<T>) {
  const id = useId();
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<Sort<T>>(defaultSort ?? null);
  const [page, setPage] = useState(0);
  const deferredQuery = useDeferredValue(query); // typing stays responsive on large tables

  const view = useMemo(() => {
    const q = deferredQuery.trim().toLowerCase();
    const out = q ? rows.filter((r) => searchKeys.some((k) => String(r[k] ?? "").toLowerCase().includes(q))) : rows.slice();
    if (sort) out.sort(comparator(sort));
    return out;
  }, [rows, deferredQuery, sort, searchKeys]);

  const pages = Math.max(1, Math.ceil(view.length / pageSize));
  const current = Math.min(page, pages - 1);
  const start = current * pageSize;
  const pageRows = view.slice(start, start + pageSize);

  const onSort = (col: Column<T>) =>
    setSort((s) =>
      s?.key === col.key ? { key: col.key, dir: s.dir === "asc" ? "desc" : "asc" } : { key: col.key, dir: col.numeric ? "desc" : "asc" },
    );

  const exportCsv = () =>
    downloadCsv(
      view,
      columns.map((c) => ({ label: c.label, value: c.csv ?? ((r: T) => r[c.key] as string | number | null) })),
      filename,
    );

  const hasTotals = columns.some((c) => c.total);

  return (
    <>
      <div className="table-toolbar">
        <label className="sr-only" htmlFor={`${id}-search`}>
          Search
        </label>
        <input
          id={`${id}-search`}
          className="input"
          type="search"
          placeholder="Search…"
          autoComplete="off"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setPage(0);
          }}
        />
        <span className="count" aria-live="polite">
          {view.length.toLocaleString()} of {rows.length.toLocaleString()} rows
        </span>
        <span className="spacer" />
        <button type="button" className="btn" onClick={exportCsv} disabled={!view.length}>
          Export CSV
        </button>
      </div>
      <div className="table-scroll">
        <table className="data-table">
          <caption className="sr-only">{caption}</caption>
          <thead>
            <tr>
              {columns.map((c) => (
                <th
                  key={c.key}
                  scope="col"
                  className={c.numeric ? "num" : undefined}
                  aria-sort={sort?.key === c.key ? (sort.dir === "asc" ? "ascending" : "descending") : "none"}
                >
                  <button type="button" onClick={() => onSort(c)}>
                    {c.label}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {pageRows.length ? (
              pageRows.map((r) => (
                <tr
                  key={rowKey(r)}
                  tabIndex={onRowClick ? 0 : undefined}
                  onClick={onRowClick ? () => onRowClick(r) : undefined}
                  onKeyDown={
                    onRowClick
                      ? (e) => {
                          if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault();
                            onRowClick(r);
                          }
                        }
                      : undefined
                  }
                >
                  {columns.map((c) => (
                    <td key={c.key} className={c.numeric ? "num" : undefined}>
                      {c.render ? c.render(r[c.key], r) : String(r[c.key] ?? "")}
                    </td>
                  ))}
                </tr>
              ))
            ) : (
              <tr>
                <td colSpan={columns.length} className="table-empty">
                  {rows.length ? "No rows match your search." : "No data for the current filters."}
                </td>
              </tr>
            )}
          </tbody>
          {hasTotals && view.length > 0 && (
            <tfoot>
              <tr>
                {columns.map((c, i) => {
                  if (i === 0) return <td key={c.key}>Total</td>;
                  if (!c.total) return <td key={c.key} />;
                  const sum = view.reduce((s, r) => s + (Number(r[c.key]) || 0), 0);
                  return (
                    <td key={c.key} className="num">
                      {c.render ? c.render(sum as T[keyof T], null) : sum}
                    </td>
                  );
                })}
              </tr>
            </tfoot>
          )}
        </table>
      </div>
      <div className="pager">
        <span>{view.length ? `${start + 1}–${Math.min(start + pageSize, view.length)} of ${view.length.toLocaleString()}` : ""}</span>
        <span className="pager-buttons">
          <button type="button" className="btn" aria-label="Previous page" disabled={current === 0} onClick={() => setPage(current - 1)}>
            {"‹ Prev"}
          </button>
          <button type="button" className="btn" aria-label="Next page" disabled={current >= pages - 1} onClick={() => setPage(current + 1)}>
            {"Next ›"}
          </button>
        </span>
      </div>
    </>
  );
}

function comparator<T>({ key, dir }: { key: keyof T; dir: "asc" | "desc" }) {
  const m = dir === "asc" ? 1 : -1;
  return (a: T, b: T) => {
    const x = a[key];
    const y = b[key];
    if (x == null && y == null) return 0;
    if (x == null) return 1; // nulls last in both directions
    if (y == null) return -1;
    if (typeof x === "number" && typeof y === "number") return (x - y) * m;
    return String(x).localeCompare(String(y), undefined, { numeric: true, sensitivity: "base" }) * m;
  };
}
