// ECharts wrapper: one place for init, theming from CSS tokens, resize, a11y and disposal.
// Every chart on the page goes through this - never call echarts.init directly in feature code.
/* global echarts */

// Read design tokens at render time so charts follow light/dark without hardcoded hex.
export function tokens() {
  const cs = getComputedStyle(document.documentElement);
  const v = (name) => cs.getPropertyValue(name).trim();
  return {
    surface: v("--surface-1"),
    text: v("--text-primary"),
    textSecondary: v("--text-secondary"),
    muted: v("--text-muted"),
    grid: v("--grid"),
    axis: v("--axis"),
    border: v("--border-strong"),
    font: v("--font-sans"),
    series: Array.from({ length: 8 }, (_, i) => v(`--series-${i + 1}`)),
    other: v("--series-other"),
    up: v("--delta-up"),
    down: v("--delta-down"),
  };
}

// Base option every chart merges into: recessive axes, token colors, readable tooltip.
export function baseOption(t) {
  return {
    backgroundColor: "transparent",
    textStyle: { fontFamily: t.font, color: t.textSecondary },
    animationDuration: matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 300,
    aria: { enabled: true, decal: { show: false } },
    grid: { left: 8, right: 16, top: 16, bottom: 8, containLabel: true },
    tooltip: {
      backgroundColor: t.surface,
      borderColor: t.border,
      borderWidth: 1,
      textStyle: { color: t.text, fontSize: 12 },
      extraCssText: "box-shadow:0 8px 24px rgba(0,0,0,.12);border-radius:6px;",
      confine: true,
    },
  };
}

export function valueAxis(t, formatter) {
  return {
    type: "value",
    axisLabel: { color: t.muted, formatter, hideOverlap: true },
    splitLine: { lineStyle: { color: t.grid } },
    axisLine: { show: false },
    axisTick: { show: false },
  };
}

export function categoryAxis(t, data, extra = {}) {
  return {
    type: "category",
    data,
    axisLabel: { color: t.muted, hideOverlap: true },
    axisLine: { lineStyle: { color: t.axis } },
    axisTick: { show: false },
    ...extra,
  };
}

/**
 * createChart(el, { label, onClick })
 *   el     - container with explicit height (CSS .chart)
 *   label  - accessible name; also give the card a visible title
 * Returns { render(buildOption), dispose() } where buildOption(tokens) returns an ECharts option.
 */
export function createChart(el, { label, onClick } = {}) {
  if (typeof echarts === "undefined") {
    el.innerHTML = '<div class="state" data-kind="error"><h2>Chart library failed to load</h2></div>';
    return { render() {}, dispose() {} };
  }
  el.setAttribute("role", "img");
  if (label) el.setAttribute("aria-label", label);

  const chart = echarts.init(el, null, { renderer: "canvas" });
  let build = null;
  if (onClick) chart.on("click", onClick);

  const ro = new ResizeObserver(() => chart.resize());
  ro.observe(el);

  const rerender = () => build && chart.setOption(build(tokens()), { notMerge: true });
  const mq = matchMedia("(prefers-color-scheme: dark)");
  mq.addEventListener("change", rerender);
  document.addEventListener("themechange", rerender);

  return {
    render(buildOption) {
      build = buildOption;
      rerender();
    },
    dispose() {
      ro.disconnect();
      mq.removeEventListener("change", rerender);
      document.removeEventListener("themechange", rerender);
      chart.dispose();
    },
  };
}
