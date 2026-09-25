// The only place echarts.init is called. Tree-shaken imports: register ONLY the chart types and
// components the dashboard uses - each one added costs bundle size (add LineChart, PieChart... as needed).
import { useEffect, useRef } from "react";
import * as echarts from "echarts/core";
import { BarChart } from "echarts/charts";
import { AriaComponent, GridComponent, LegendComponent, TooltipComponent } from "echarts/components";
import { CanvasRenderer } from "echarts/renderers";
import type { EChartsCoreOption, ECElementEvent } from "echarts/core";

echarts.use([BarChart, GridComponent, TooltipComponent, LegendComponent, AriaComponent, CanvasRenderer]);

interface Props {
  option: EChartsCoreOption;
  /** Accessible name. The card should also carry a visible title. */
  label: string;
  className?: string;
  onClick?: (e: ECElementEvent) => void;
}

export function EChart({ option, label, className = "chart", onClick }: Props) {
  const el = useRef<HTMLDivElement>(null);
  const chart = useRef<echarts.ECharts | null>(null);
  const clickRef = useRef(onClick);
  useEffect(() => {
    clickRef.current = onClick;
  }, [onClick]);

  // Mount/unmount: init, resize observer, click bridge, dispose.
  useEffect(() => {
    const node = el.current!;
    const c = echarts.init(node, null, { renderer: "canvas" });
    chart.current = c;
    c.on("click", (e) => clickRef.current?.(e as ECElementEvent));
    const ro = new ResizeObserver(() => c.resize());
    ro.observe(node);
    return () => {
      ro.disconnect();
      c.dispose();
      chart.current = null;
    };
  }, []);

  // notMerge: the option is the full truth each render; stale series from a previous filter must not linger.
  useEffect(() => {
    chart.current?.setOption(option, { notMerge: true });
  }, [option]);

  return <div ref={el} className={className} role="img" aria-label={label} />;
}
