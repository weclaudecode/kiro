// Filter bar: date-range presets + multi-select dimensions + reset. One row, above everything it filters.
// Renders from store state; every interaction is a dispatched action - no component-local filter state.
import { esc } from "../format.js";

const RANGE_LABELS = { "7d": "7D", "30d": "30D", "90d": "90D", mtd: "MTD", "prev-month": "Last month", all: "All" };

/**
 * createFilterBar(root, store, { dimensions: [{ key, label, options: string[] }] })
 */
export function createFilterBar(root, store, { dimensions }) {
  root.innerHTML = `
    <div class="field">
      <span class="field-label" id="range-label">Period</span>
      <div class="segmented" role="group" aria-labelledby="range-label">
        ${Object.entries(RANGE_LABELS)
          .map(([k, v]) => `<button type="button" data-range="${k}" aria-pressed="false">${v}</button>`)
          .join("")}
      </div>
    </div>
    ${dimensions
      .map(
        (d) => `
      <div class="field">
        <span class="field-label" id="lbl-${d.key}">${esc(d.label)}</span>
        <details class="multiselect" data-dim="${d.key}">
          <summary aria-labelledby="lbl-${d.key}"><span class="ms-value">All</span></summary>
          <div class="multiselect-panel" role="group" aria-labelledby="lbl-${d.key}">
            <div class="panel-actions">
              <button type="button" class="link-btn" data-ms="all">Select all</button>
              <button type="button" class="link-btn" data-ms="none">Clear</button>
            </div>
            ${d.options
              .map((o) => `<label><input type="checkbox" value="${esc(o)}"> ${esc(o)}</label>`)
              .join("")}
          </div>
        </details>
      </div>`,
      )
      .join("")}
    <div class="filter-actions">
      <button type="button" class="btn" data-action="reset">Reset filters</button>
    </div>`;

  root.addEventListener("click", (e) => {
    const rangeBtn = e.target.closest("[data-range]");
    if (rangeBtn) return store.dispatch({ type: "range/set", value: rangeBtn.dataset.range });
    if (e.target.closest('[data-action="reset"]')) return store.dispatch({ type: "filters/reset" });
    const ms = e.target.closest("[data-ms]");
    if (ms) {
      const dim = ms.closest("details").dataset.dim;
      // "Select all" == no filter. Empty array means all; we never store the full list.
      store.dispatch({ type: "dimension/set", dimension: dim, values: [] });
    }
  });

  root.addEventListener("change", (e) => {
    if (e.target.type !== "checkbox") return;
    const dim = e.target.closest("details").dataset.dim;
    store.dispatch({ type: "dimension/toggle", dimension: dim, value: e.target.value });
  });

  // Close any open popover on outside click or Escape.
  document.addEventListener("click", (e) => {
    root.querySelectorAll("details[open]").forEach((d) => !d.contains(e.target) && d.removeAttribute("open"));
  });
  root.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    const open = e.target.closest("details[open]");
    if (open) {
      open.removeAttribute("open");
      open.querySelector("summary").focus();
    }
  });

  function sync(state) {
    root.querySelectorAll("[data-range]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.range === state.range)));
    root.querySelectorAll("details[data-dim]").forEach((det) => {
      const selected = state[det.dataset.dim];
      det.querySelectorAll("input[type=checkbox]").forEach((cb) => (cb.checked = selected.includes(cb.value)));
      det.querySelector(".ms-value").textContent =
        selected.length === 0 ? "All" : selected.length === 1 ? selected[0] : `${selected.length} selected`;
    });
  }

  sync(store.getState());
  store.subscribe(sync);
}
