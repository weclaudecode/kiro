// Stat tile: a single headline number is not a chart - no ECharts here.
import type { Direction } from "../lib/format";

interface Props {
  label: string;
  value: string;
  delta?: { text: string; dir: Direction } | null;
  foot?: string;
  spark?: number[];
  /** Render a name (not a number): smaller, single line, ellipsis. Pass the full name as title. */
  text?: boolean;
  title?: string;
}

export function KpiCard({ label, value, delta, foot, spark, text = false, title }: Props) {
  return (
    <article className="card kpi">
      <p className="kpi-label">{label}</p>
      <p className={text ? "kpi-value kpi-value-text" : "kpi-value"} title={title}>
        {value}
      </p>
      <div className="kpi-foot">
        {delta && (
          <>
            <span className="delta" data-dir={delta.dir}>
              {delta.text}
            </span>
            <span className="sr-only">{delta.dir === "up" ? "increase" : delta.dir === "down" ? "decrease" : "no change"}</span>
          </>
        )}
        {foot && <span>{foot}</span>}
      </div>
      {spark && spark.length > 1 && <Sparkline values={spark} />}
    </article>
  );
}

export function KpiSkeleton() {
  return (
    <article className="card kpi" aria-hidden="true">
      <div className="skeleton" style={{ height: 14, width: "40%" }} />
      <div className="skeleton" style={{ height: 30, width: "70%", marginTop: 10 }} />
      <div className="skeleton" style={{ height: 12, width: "50%", marginTop: 10 }} />
    </article>
  );
}

function Sparkline({ values }: { values: number[] }) {
  const w = 200;
  const h = 36;
  const min = Math.min(...values);
  const span = Math.max(...values) - min || 1;
  const points = values
    .map((v, i) => `${((i / (values.length - 1)) * w).toFixed(1)},${(h - 2 - ((v - min) / span) * (h - 4)).toFixed(1)}`)
    .join(" ");
  return (
    <svg className="kpi-spark" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" width="100%" aria-hidden="true">
      <polyline
        points={points}
        fill="none"
        stroke="var(--series-1)"
        strokeWidth={2}
        vectorEffect="non-scaling-stroke"
        strokeLinejoin="round"
      />
    </svg>
  );
}
