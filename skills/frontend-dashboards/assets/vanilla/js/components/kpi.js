// KPI / stat tile: label, hero value, optional delta and inline SVG sparkline.
// A single headline number is not a chart - don't reach for ECharts here.
import { esc } from "../format.js";

/**
 * renderKpi(el, { label, value, delta?: { text, dir, abs? }, foot?, spark?: number[], title?, text? })
 * text: true renders a name (not a number) at a smaller size with ellipsis; pass the full name as title.
 * value and foot are plain text (escaped). delta.dir: "up" | "down" | "flat".
 */
export function renderKpi(el, { label, value, delta, foot, spark, title, text = false }) {
  const deltaHtml = delta
    ? `<span class="delta" data-dir="${delta.dir}">${esc(delta.text)}</span>` +
      `<span class="sr-only">${delta.dir === "up" ? "increase" : delta.dir === "down" ? "decrease" : "no change"}</span>`
    : "";
  el.innerHTML = `
    <p class="kpi-label">${esc(label)}</p>
    <p class="kpi-value${text ? " kpi-value-text" : ""}"${title ? ` title="${esc(title)}"` : ""}>${esc(value)}</p>
    <div class="kpi-foot">${deltaHtml}${foot ? `<span>${esc(foot)}</span>` : ""}</div>
    ${spark?.length > 1 ? sparkline(spark) : ""}`;
}

export function renderKpiSkeleton(el) {
  el.innerHTML = `
    <div class="skeleton" style="height:14px;width:40%"></div>
    <div class="skeleton" style="height:30px;width:70%;margin-top:10px"></div>
    <div class="skeleton" style="height:12px;width:50%;margin-top:10px"></div>`;
}

function sparkline(values) {
  const w = 200;
  const h = 36;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  const pts = values.map((v, i) => `${((i / (values.length - 1)) * w).toFixed(1)},${(h - 2 - ((v - min) / span) * (h - 4)).toFixed(1)}`);
  return `<svg class="kpi-spark" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" width="100%" aria-hidden="true">
    <polyline points="${pts.join(" ")}" fill="none" stroke="var(--series-1)" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>
  </svg>`;
}
