// Feature composition. Each widget subscribes to its own narrow selector, so a change re-renders
// only the widgets whose inputs changed. Generic pieces live in components/; chart options in charts/.
import { useCallback, useEffect, useMemo } from "react";
import { useAppDispatch, useAppSelector } from "./store/hooks";
import { loadCostData } from "./store/dataSlice";
import { dimensionToggled, groupBySet, GROUP_BYS } from "./store/filtersSlice";
import {
  selectByAccount,
  selectDataset,
  selectError,
  selectFilters,
  selectGrouped,
  selectKpis,
  selectMovers,
  selectPeriod,
  selectStatus,
  selectTop,
  selectTrend,
} from "./store/selectors";
import { awsServiceLabel, currency, delta, longDate, monthName, percent, shortDate } from "./lib/format";
import type { Dimension, GroupBy, GroupedRow } from "./lib/types";
import { accountOption, moversOption, trendOption } from "./charts/options";
import { useChartTokens } from "./charts/theme";
import { Card } from "./components/Card";
import { DataTable, type Column } from "./components/DataTable";
import { EChart } from "./components/EChart";
import { FilterBar } from "./components/FilterBar";
import { KpiCard, KpiSkeleton } from "./components/KpiCard";
import { ThemeToggle } from "./components/ThemeToggle";

const DATA_URL = "data/costs.json"; // relative: works under any base path
const GROUP_LABEL: Record<GroupBy, string> = { service: "Service", accountName: "Account", environment: "Environment", region: "Region" };
const round = (v: number | null, dp: number) => (v == null ? null : Number(v.toFixed(dp)));
const GROUP_DIM: Record<GroupBy, Dimension> = { service: "services", accountName: "accounts", environment: "environments", region: "regions" };

function useMoney() {
  const code = useAppSelector((s) => s.data.dataset?.meta.currency ?? "USD");
  return useMemo(
    () => ({
      money: (v: number) => currency(v, code),
      cents: (v: number) => currency(v, code, { decimals: 2 }), // tables: fixed decimals so columns align
      compact: (v: number) => currency(v, code, { compact: true }),
    }),
    [code],
  );
}

export function App() {
  const dispatch = useAppDispatch();
  const status = useAppSelector(selectStatus);
  const error = useAppSelector(selectError);
  const ds = useAppSelector(selectDataset);

  useEffect(() => {
    dispatch(loadCostData(DATA_URL));
  }, [dispatch]);

  return (
    <>
      <header className="app-header">
        <div>
          <h1>AWS Cost Analysis</h1>
          <p className="subtitle">
            {ds
              ? `${ds.meta.metric ?? "Cost"} · ${ds.meta.currency ?? "USD"} · data ${longDate(ds.meta.start)} – ${longDate(ds.meta.end)}` +
                (ds.meta.source ? ` · source: ${ds.meta.source}` : "")
              : status === "failed"
                ? "Data unavailable"
                : "Loading data…"}
          </p>
        </div>
        <ThemeToggle />
      </header>
      <main className="app-main">
        {status === "failed" ? (
          <section className="card state" data-kind="error" role="alert">
            <h2>Could not load the dashboard data</h2>
            <p>{error}</p>
          </section>
        ) : ds ? (
          <Dashboard />
        ) : (
          <section className="kpi-grid" aria-busy="true" aria-label="Loading">
            <KpiSkeleton />
            <KpiSkeleton />
            <KpiSkeleton />
            <KpiSkeleton />
          </section>
        )}
      </main>
    </>
  );
}

function Dashboard() {
  const ds = useAppSelector(selectDataset)!;
  return (
    <>
      <FilterBar
        dimensions={[
          { key: "accounts", label: "Account", options: ds.dims.accounts },
          { key: "environments", label: "Environment", options: ds.dims.environments },
          { key: "services", label: "Service", options: ds.dims.services },
          { key: "regions", label: "Region", options: ds.dims.regions },
        ]}
      />
      <KpiRow />
      <section className="grid">
        <TrendCard />
        <AccountCard />
        <MoversCard />
        <BreakdownCard />
      </section>
    </>
  );
}

function KpiRow() {
  const k = useAppSelector(selectKpis);
  const p = useAppSelector(selectPeriod);
  const daily = useAppSelector(selectTrend).daily;
  const top = useAppSelector(selectTop);
  const groupBy = useAppSelector((s) => s.filters.groupBy);
  const end = useAppSelector((s) => s.data.dataset?.meta.end ?? "");
  const { money } = useMoney();
  if (!k || !p) return null;
  const period = `${shortDate(p.range.start)} – ${shortDate(p.range.end)}`;
  const d = delta(k.spend, k.prevSpend);
  return (
    <section className="kpi-grid" aria-label="Key figures">
      <KpiCard label="Total spend" value={money(k.spend)} delta={d} foot={d ? `vs previous ${p.days} days` : period} spark={daily} />
      <KpiCard label="Average daily spend" value={money(k.avgDaily)} foot={`over ${p.days} days · ${period}`} />
      <KpiCard label={`Forecast, ${monthName(end)}`} value={money(k.forecast)} foot="Month-to-date + trailing 7-day run rate" />
      <KpiCard
        label={`Top ${GROUP_LABEL[groupBy].toLowerCase()}`}
        value={top ? (groupBy === "service" ? awsServiceLabel(top.name) : top.name) : "—"}
        title={top?.name}
        text
        foot={top ? `${money(top.cost)} · ${percent(top.share)} of spend` : "No spend in range"}
      />
    </section>
  );
}

function TrendCard() {
  const t = useChartTokens();
  const { dates, series } = useAppSelector(selectTrend);
  const { money, compact } = useMoney();
  const option = useMemo(() => trendOption(t, dates, series, money, compact), [t, dates, series, money, compact]);
  return (
    <Card title="Daily spend by service" subtitle="Top 7 services by total spend; the rest grouped as Other">
      <EChart option={option} label="Stacked bar chart of daily spend by service" />
    </Card>
  );
}

function AccountCard() {
  const dispatch = useAppDispatch();
  const t = useChartTokens();
  const byAccount = useAppSelector(selectByAccount);
  const selected = useAppSelector((s) => s.filters.accounts);
  const { money, compact } = useMoney();
  const option = useMemo(() => accountOption(t, byAccount, selected, money, compact), [t, byAccount, selected, money, compact]);
  const onClick = useCallback((e: { name: string }) => dispatch(dimensionToggled({ dimension: "accounts", value: e.name })), [dispatch]);
  return (
    <Card span={6} title="Spend by account" subtitle="Click a bar to filter to that account">
      <EChart option={option} className="chart chart-sm" label="Bar chart of spend by account" onClick={onClick} />
    </Card>
  );
}

function MoversCard() {
  const t = useChartTokens();
  const movers = useAppSelector(selectMovers);
  const p = useAppSelector(selectPeriod);
  const { money, compact } = useMoney();
  const option = useMemo(() => moversOption(t, movers, money, compact), [t, movers, money, compact]);
  const subtitle = p?.hasPrev
    ? `Change vs ${shortDate(p.prev.start)} – ${shortDate(p.prev.end)}, by service`
    : "No previous period in the data for this range";
  return (
    <Card span={6} title="Top movers" subtitle={subtitle}>
      <EChart option={option} className="chart chart-sm" label="Diverging bar chart of change in spend by service" />
    </Card>
  );
}

function BreakdownCard() {
  const dispatch = useAppDispatch();
  const rows = useAppSelector(selectGrouped);
  const { groupBy } = useAppSelector(selectFilters);
  const end = useAppSelector((s) => s.data.dataset?.meta.end ?? "");
  const { cents } = useMoney();

  const columns = useMemo<Column<GroupedRow>[]>(() => {
    const na = <span className="muted">n/a</span>;
    return [
      { key: "name", label: "Name" },
      { key: "cost", label: "Cost", numeric: true, total: true, render: (v) => cents(v as number), csv: (r) => round(r.cost, 2) },
      {
        key: "share",
        label: "Share",
        numeric: true,
        csv: (r) => round(r.share, 4),
        render: (v) => (
          <span className="bar-cell">
            <span className="bar" style={{ width: `${((v as number) * 100).toFixed(1)}%` }} />
            {percent(v as number)}
          </span>
        ),
      },
      { key: "prior", label: "Prev. period", numeric: true, total: true, render: (v) => (v == null ? na : cents(v as number)), csv: (r) => round(r.prior, 2) },
      { key: "change", label: "Change", numeric: true, total: true, render: (v) => (v == null ? na : <Delta value={v as number} fmt={cents} />), csv: (r) => round(r.change, 2) },
      {
        key: "changePct",
        label: "Change %",
        numeric: true,
        csv: (r) => round(r.changePct, 4),
        render: (v, row) =>
          v != null ? (
            <Delta value={v as number} fmt={(x) => percent(x)} />
          ) : row?.prior == null ? (
            na
          ) : (
            <span className="muted">new</span> // prior was 0
          ),
      },
    ];
  }, [cents]);

  return (
    <Card
      title="Cost breakdown"
      subtitle="Click a row to filter the dashboard to it"
      flush
      actions={
        <div className="field">
          <label htmlFor="group-by">Group by</label>
          <select id="group-by" className="select" value={groupBy} onChange={(e) => dispatch(groupBySet(e.target.value as GroupBy))}>
            {GROUP_BYS.map((g) => (
              <option key={g} value={g}>
                {GROUP_LABEL[g]}
              </option>
            ))}
          </select>
        </div>
      }
    >
      <DataTable
        rows={rows}
        rowKey={(r) => r.name}
        columns={columns}
        searchKeys={["name"]}
        defaultSort={{ key: "cost", dir: "desc" }}
        pageSize={15}
        filename={`aws-cost-breakdown-${end}.csv`}
        caption="Cost breakdown with previous-period comparison"
        onRowClick={(r) => dispatch(dimensionToggled({ dimension: GROUP_DIM[groupBy], value: r.name }))}
      />
    </Card>
  );
}

function Delta({ value, fmt }: { value: number; fmt: (v: number) => string }) {
  const dir = Math.abs(value) < 1e-9 ? "flat" : value > 0 ? "up" : "down";
  const sign = value > 0 ? "+" : value < 0 ? "−" : "";
  return (
    <span className="delta" data-dir={dir}>
      {sign}
      {fmt(Math.abs(value))}
    </span>
  );
}
