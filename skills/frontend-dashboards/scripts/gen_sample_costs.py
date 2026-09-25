#!/usr/bin/env python3
"""Generate a realistic AWS cost sample dataset in the dashboard data contract.

Deterministic (seeded) so screenshots and tests are stable. Stdlib only.

Usage:
    python3 gen_sample_costs.py                      # 120 days ending yesterday -> stdout
    python3 gen_sample_costs.py --days 90 --end 2026-09-24 -o data/costs.json
    python3 gen_sample_costs.py --seed 7 --spike     # inject a cost spike to test anomaly UI

Contract: see references/data-contract.md.
"""

from __future__ import annotations

import argparse
import json
import os
import math
import random
import sys
from datetime import date, datetime, timedelta, timezone

ACCOUNTS = [
    # id, name, environment, scale
    ("111111111111", "prod-app", "prod", 1.00),
    ("222222222222", "prod-data", "prod", 0.70),
    ("333333333333", "staging", "staging", 0.25),
    ("444444444444", "dev", "dev", 0.15),
    ("555555555555", "shared-services", "shared", 0.20),
]

# service, base daily USD at scale 1.0, weekday sensitivity, regions
SERVICES = [
    ("Amazon Elastic Compute Cloud - Compute", 410.0, 0.10, ["us-east-1", "eu-west-1"]),
    ("Amazon Relational Database Service", 260.0, 0.00, ["us-east-1"]),
    ("Amazon Simple Storage Service", 95.0, 0.02, ["us-east-1", "eu-west-1"]),
    ("AWS Lambda", 48.0, 0.35, ["us-east-1", "eu-west-1"]),
    ("Amazon DynamoDB", 62.0, 0.25, ["us-east-1"]),
    ("Amazon CloudFront", 38.0, 0.30, ["global"]),
    ("Amazon Elastic Container Service", 120.0, 0.05, ["us-east-1"]),
    ("Amazon CloudWatch", 41.0, 0.05, ["us-east-1", "eu-west-1"]),
    ("Amazon Virtual Private Cloud", 55.0, 0.00, ["us-east-1", "eu-west-1"]),
    ("AWS Key Management Service", 6.0, 0.00, ["us-east-1"]),
    ("Amazon Bedrock", 70.0, 0.40, ["us-east-1"]),
    ("Amazon Simple Queue Service", 4.0, 0.30, ["us-east-1"]),
]

# Some services do not run in some accounts (keeps the dataset lumpy like real CUR data).
SKIP = {
    ("dev", "Amazon CloudFront"),
    ("shared", "Amazon Bedrock"),
    ("shared", "Amazon DynamoDB"),
    ("staging", "Amazon Bedrock"),
}


def build_rows(days: int, end: date, seed: int, spike: bool) -> list[dict]:
    rng = random.Random(seed)
    start = end - timedelta(days=days - 1)
    rows: list[dict] = []
    for d in range(days):
        day = start + timedelta(days=d)
        weekend = day.weekday() >= 5
        growth = 1.0 + 0.0025 * d  # ~0.25%/day organic growth
        for acct_id, acct_name, env, scale in ACCOUNTS:
            for service, base, weekday_sens, regions in SERVICES:
                if (env, service) in SKIP:
                    continue
                for i, region in enumerate(regions):
                    region_share = 0.75 if i == 0 and len(regions) > 1 else (0.25 if len(regions) > 1 else 1.0)
                    seasonal = 1.0 - (weekday_sens if weekend else 0.0)
                    wobble = 1.0 + 0.06 * math.sin(d / 5.0 + len(service)) + rng.gauss(0, 0.04)
                    cost = base * scale * region_share * seasonal * growth * max(wobble, 0.5)
                    if spike and env == "prod" and service == "Amazon Bedrock" and d >= days - 6:
                        cost *= 3.2  # the "why did prod jump this week?" story
                    if env in {"dev", "staging"} and weekend:
                        cost *= 0.6  # scheduled shutdowns
                    rows.append(
                        {
                            "date": day.isoformat(),
                            "accountId": acct_id,
                            "accountName": acct_name,
                            "environment": env,
                            "service": service,
                            "region": region,
                            "cost": round(cost, 2),
                        }
                    )
    return rows


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--days", type=int, default=120)
    p.add_argument("--end", type=date.fromisoformat, default=date.today() - timedelta(days=1))
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--spike", action="store_true", help="inject a prod Bedrock spike in the last 6 days")
    p.add_argument("-o", "--output", help="write to file instead of stdout")
    args = p.parse_args()

    rows = build_rows(args.days, args.end, args.seed, args.spike)
    doc = {
        "meta": {
            "schemaVersion": 1,
            "source": "sample",
            "metric": "UnblendedCost",
            "currency": "USD",
            "granularity": "DAILY",
            "start": rows[0]["date"],
            "end": rows[-1]["date"],
            "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "notes": "Synthetic data. Credits, refunds and tax excluded.",
        },
        "rows": rows,
    }
    out = json.dumps(doc, separators=(",", ":"))
    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(out)
        print(f"wrote {len(rows)} rows to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
