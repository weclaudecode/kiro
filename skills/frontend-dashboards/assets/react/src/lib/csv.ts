export interface CsvColumn<T> {
  label: string;
  value: (row: T) => string | number | null | undefined;
}

/** Download the whole filtered+sorted view (not just the visible page), raw values not formatted text. */
export function downloadCsv<T>(rows: readonly T[], columns: CsvColumn<T>[], filename: string): void {
  const cell = (v: string | number | null | undefined): string => {
    if (v == null) return "";
    let s = String(v);
    // CSV/formula injection guard: a string cell starting with = + - @ runs as a formula in Excel.
    if (typeof v === "string" && /^[=+\-@\t\r]/.test(s)) s = `'${s}`;
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [columns.map((c) => cell(c.label)).join(",")];
  for (const r of rows) lines.push(columns.map((c) => cell(c.value(r))).join(","));
  const blob = new Blob([`﻿${lines.join("\r\n")}`], { type: "text/csv;charset=utf-8" });
  const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: filename });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 0);
}
