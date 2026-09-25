#!/usr/bin/env python3
"""Convert cost exports into the dashboard data contract, or validate a contract file.

Stdlib only. Never calls AWS itself: you run the export, this reshapes it.

Subcommands:
    ce        Cost Explorer `get-cost-and-usage` JSON (one or more pages) -> contract
    csv       CUR / Athena / spreadsheet CSV with contract column names -> contract
    validate  Check a contract file and print a summary (exit 1 on errors)

Examples:
    # Cost Explorer (bills $0.01 per API call; one call per page)
    aws ce get-cost-and-usage \\
      --time-period Start=2026-06-01,End=2026-09-25 --granularity DAILY \\
      --metrics UnblendedCost \\
      --group-by Type=DIMENSION,Key=LINKED_ACCOUNT Type=DIMENSION,Key=SERVICE \\
      > ce-page1.json
    python3 to_rows.py ce ce-page1.json --accounts accounts.json -o data/costs.json

    # Athena over CUR 2.0 (query in references/data-contract.md), downloaded as CSV
    python3 to_rows.py csv athena-results.csv -o data/costs.json

    python3 to_rows.py validate data/costs.json

accounts.json maps account id -> name/environment, because Cost Explorer allows only
two group-by keys and the dashboard needs account, environment and service:
    {"111111111111": {"name": "prod-app", "environment": "prod"}}
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from datetime import datetime, timezone

REQUIRED = ("date", "accountId", "accountName", "environment", "service", "region", "cost")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def envelope(rows: list[dict], source: str, metric: str, currency: str) -> dict:
    rows.sort(key=lambda r: (r["date"], r["accountId"], r["service"], r["region"]))
    return {
        "meta": {
            "schemaVersion": 1,
            "source": source,
            "metric": metric,
            "currency": currency,
            "granularity": "DAILY",
            "start": rows[0]["date"] if rows else None,
            "end": rows[-1]["date"] if rows else None,
            "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        },
        "rows": rows,
    }


def from_ce(paths: list[str], accounts_path: str | None) -> dict:
    accounts = {}
    if accounts_path:
        with open(accounts_path, encoding="utf-8") as fh:
            accounts = json.load(fh)
    rows: list[dict] = []
    metric, currency = None, None
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            page = json.load(fh)
        # CE returns keys in the order of --group-by; we require LINKED_ACCOUNT then SERVICE.
        defs = [g.get("Key") for g in page.get("GroupDefinitions", [])]
        if defs != ["LINKED_ACCOUNT", "SERVICE"]:
            raise SystemExit(f"{path}: expected --group-by LINKED_ACCOUNT then SERVICE, got {defs}")
        for period in page.get("ResultsByTime", []):
            day = period["TimePeriod"]["Start"]
            for group in period.get("Groups", []):
                acct_id, service = group["Keys"]
                (metric_name, m), = group["Metrics"].items()
                metric = metric or metric_name
                currency = currency or m.get("Unit", "USD")
                amount = round(float(m["Amount"]), 4)
                if amount == 0:
                    continue
                info = accounts.get(acct_id, {})
                rows.append(
                    {
                        "date": day,
                        "accountId": acct_id,
                        "accountName": info.get("name", acct_id),
                        "environment": info.get("environment", "unmapped"),
                        "service": service,
                        "region": "all",
                        "cost": amount,
                    }
                )
    return envelope(rows, "cost-explorer", metric or "UnblendedCost", currency or "USD")


def from_csv(path: str, metric: str, currency: str) -> dict:
    rows: list[dict] = []
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit(f"{path}: missing columns {missing}; alias them in the query")
        for r in reader:
            cost = float(r["cost"] or 0)
            if cost == 0:
                continue
            rows.append({k: r[k] for k in REQUIRED[:-1]} | {"cost": round(cost, 4)})
    return envelope(rows, "csv", metric, currency)


def validate(path: str) -> int:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    errors: list[str] = []
    meta, rows = doc.get("meta"), doc.get("rows")
    if not isinstance(meta, dict):
        errors.append("meta missing")
    elif meta.get("schemaVersion") != 1:
        errors.append(f"unsupported schemaVersion {meta.get('schemaVersion')}")
    if not isinstance(rows, list):
        errors.append("rows missing")
        rows = []
    for i, r in enumerate(rows):
        missing = [k for k in REQUIRED if k not in r]
        if missing:
            errors.append(f"row {i}: missing {missing}")
        elif not DATE_RE.match(str(r["date"])):
            errors.append(f"row {i}: date {r['date']!r} not YYYY-MM-DD")
        elif not isinstance(r["cost"], (int, float)):
            errors.append(f"row {i}: cost must be a number, got {type(r['cost']).__name__}")
        if len(errors) >= 20:
            errors.append("... (stopping after 20 errors)")
            break
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    total = sum(r["cost"] for r in rows)
    dims = {k: len({r[k] for r in rows}) for k in ("accountId", "environment", "service", "region")}
    size_kb = len(json.dumps(doc, separators=(",", ":"))) / 1024
    print(f"ok: {len(rows)} rows, {meta.get('start')}..{meta.get('end')}, total {total:,.2f} {meta.get('currency')}")
    print(f"    distinct: {dims}; payload {size_kb:,.0f} KB")
    if len(rows) > 200_000 or size_kb > 20_000:
        print("    warn: large for in-browser aggregation; pre-aggregate (see references/performance.md)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    ce = sub.add_parser("ce")
    ce.add_argument("pages", nargs="+")
    ce.add_argument("--accounts")
    ce.add_argument("-o", "--output")
    cs = sub.add_parser("csv")
    cs.add_argument("path")
    cs.add_argument("--metric", default="UnblendedCost")
    cs.add_argument("--currency", default="USD")
    cs.add_argument("-o", "--output")
    va = sub.add_parser("validate")
    va.add_argument("path")
    args = p.parse_args()

    if args.cmd == "validate":
        return validate(args.path)
    doc = from_ce(args.pages, args.accounts) if args.cmd == "ce" else from_csv(args.path, args.metric, args.currency)
    out = json.dumps(doc, separators=(",", ":"))
    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(out)
        print(f"wrote {len(doc['rows'])} rows to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
