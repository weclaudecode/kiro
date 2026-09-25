// Data table: search, sort, pagination, totals row, CSV export. No library.
// Sort/search/page are LOCAL UI state (only this table cares); dashboard filters come in via setRows().
import { esc } from "../format.js";

/**
 * createTable(root, options)
 *   columns: [{ key, label, numeric?, total?, render?(value, row) -> HTML string, csv?(value, row) -> string }]
 *   render() is also called for the footer total with row = null (value null when the column is all null)
 *   searchKeys: keys matched by the search box (case-insensitive substring)
 *   defaultSort: { key, dir: "asc" | "desc" }
 *   pageSize: rows per page (default 25)
 *   filename: CSV download name
 *   caption: accessible table caption
 *   onRowClick?(row)
 */
export function createTable(root, options) {
  const { columns, searchKeys = [], pageSize = 25, filename = "export.csv", caption = "", onRowClick } = options;
  const ui = { sort: options.defaultSort ?? null, query: "", page: 0 };
  let rows = [];
  let view = [];

  root.innerHTML = `
    <div class="table-toolbar">
      <label class="sr-only" for="${root.id}-search">Search</label>
      <input id="${root.id}-search" class="input" type="search" placeholder="Search…" autocomplete="off">
      <span class="count" aria-live="polite"></span>
      <span class="spacer"></span>
      <button type="button" class="btn" data-action="csv">Export CSV</button>
    </div>
    <div class="table-scroll">
      <table class="data-table">
        <caption class="sr-only">${esc(caption)}</caption>
        <thead><tr>${columns
          .map(
            (c) =>
              `<th scope="col" class="${c.numeric ? "num" : ""}" data-key="${esc(c.key)}" aria-sort="none">` +
              `<button type="button">${esc(c.label)}</button></th>`,
          )
          .join("")}</tr></thead>
        <tbody></tbody>
        <tfoot></tfoot>
      </table>
    </div>
    <div class="pager">
      <span class="pager-info"></span>
      <span class="pager-buttons">
        <button type="button" class="btn" data-page="prev" aria-label="Previous page">‹ Prev</button>
        <button type="button" class="btn" data-page="next" aria-label="Next page">Next ›</button>
      </span>
    </div>`;

  const $ = (sel) => root.querySelector(sel);
  const search = $("input[type=search]");
  let timer;
  search.addEventListener("input", () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      ui.query = search.value.trim().toLowerCase();
      ui.page = 0;
      update();
    }, 150);
  });

  $("thead").addEventListener("click", (e) => {
    const th = e.target.closest("th");
    if (!th) return;
    const key = th.dataset.key;
    const col = columns.find((c) => c.key === key);
    // First click: numbers sort high-to-low (what cost users want), text A-Z.
    const firstDir = col.numeric ? "desc" : "asc";
    ui.sort = ui.sort?.key === key ? { key, dir: ui.sort.dir === "asc" ? "desc" : "asc" } : { key, dir: firstDir };
    update();
  });

  root.querySelector(".pager").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-page]");
    if (!btn) return;
    ui.page += btn.dataset.page === "next" ? 1 : -1;
    update();
  });

  $('[data-action="csv"]').addEventListener("click", () => downloadCsv(view, columns, filename));

  if (onRowClick) {
    $("tbody").addEventListener("click", (e) => {
      const tr = e.target.closest("tr[data-index]");
      if (tr) onRowClick(view[Number(tr.dataset.index)]);
    });
    $("tbody").addEventListener("keydown", (e) => {
      const tr = e.target.closest("tr[data-index]");
      if (tr && (e.key === "Enter" || e.key === " ")) {
        e.preventDefault();
        onRowClick(view[Number(tr.dataset.index)]);
      }
    });
  }

  function update() {
    const q = ui.query;
    view = q ? rows.filter((r) => searchKeys.some((k) => String(r[k] ?? "").toLowerCase().includes(q))) : rows.slice();
    if (ui.sort) view.sort(comparator(ui.sort));

    const pages = Math.max(1, Math.ceil(view.length / pageSize));
    ui.page = Math.min(Math.max(ui.page, 0), pages - 1);
    const startIdx = ui.page * pageSize;
    const pageRows = view.slice(startIdx, startIdx + pageSize);

    root.querySelectorAll("thead th").forEach((th) => {
      th.setAttribute("aria-sort", ui.sort?.key === th.dataset.key ? (ui.sort.dir === "asc" ? "ascending" : "descending") : "none");
    });

    $("tbody").innerHTML = pageRows.length
      ? pageRows
          .map(
            (r, i) =>
              `<tr data-index="${startIdx + i}"${onRowClick ? ' tabindex="0"' : ""}>${columns
                .map((c) => `<td class="${c.numeric ? "num" : ""}">${c.render ? c.render(r[c.key], r) : esc(r[c.key] ?? "")}</td>`)
                .join("")}</tr>`,
          )
          .join("")
      : `<tr><td colspan="${columns.length}" class="table-empty">${
          rows.length ? "No rows match your search." : "No data for the current filters."
        }</td></tr>`;

    const totals = columns.some((c) => c.total)
      ? `<tr>${columns
          .map((c, i) => {
            if (i === 0) return "<td>Total</td>";
            if (!c.total) return "<td></td>";
            // All-null column (e.g. no previous period): total is "n/a", not a fake 0.
            const sum = view.every((r) => r[c.key] == null) ? null : view.reduce((s, r) => s + (Number(r[c.key]) || 0), 0);
            return `<td class="num">${c.render ? c.render(sum, null) : esc(sum ?? "")}</td>`;
          })
          .join("")}</tr>`
      : "";
    $("tfoot").innerHTML = view.length ? totals : "";

    $(".count").textContent = `${view.length.toLocaleString()} of ${rows.length.toLocaleString()} rows`;
    $(".pager-info").textContent = view.length
      ? `${startIdx + 1}–${Math.min(startIdx + pageSize, view.length)} of ${view.length.toLocaleString()}`
      : "";
    root.querySelector('[data-page="prev"]').disabled = ui.page === 0;
    root.querySelector('[data-page="next"]').disabled = ui.page >= pages - 1;
  }

  return {
    setRows(next) {
      rows = next;
      update();
    },
  };
}

function comparator({ key, dir }) {
  const m = dir === "asc" ? 1 : -1;
  return (a, b) => {
    const x = a[key];
    const y = b[key];
    // Nulls (e.g. "no prior period") always sort last, whichever direction.
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    if (typeof x === "number" && typeof y === "number") return (x - y) * m;
    return String(x).localeCompare(String(y), undefined, { numeric: true, sensitivity: "base" }) * m;
  };
}

// CSV of the whole filtered+sorted view (not just the visible page), raw values not formatted text.
export function downloadCsv(rows, columns, filename) {
  const cell = (v) => {
    if (v == null) return "";
    let s = String(v);
    // CSV/formula injection guard: a string cell starting with = + - @ runs as a formula in Excel.
    if (typeof v === "string" && /^[=+\-@\t\r]/.test(s)) s = `'${s}`;
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [columns.map((c) => cell(c.label)).join(",")];
  for (const r of rows) lines.push(columns.map((c) => cell(c.csv ? c.csv(r[c.key], r) : r[c.key])).join(","));
  const blob = new Blob([`﻿${lines.join("\r\n")}`], { type: "text/csv;charset=utf-8" });
  const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: filename });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 0);
}
