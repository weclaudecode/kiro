#!/usr/bin/env bash
# Run a Powerpipe benchmark or dashboard across one or all environments and
# write timestamped artifacts to out/<env>/. Read-only: it only queries AWS
# through Steampipe and writes local files — it never mutates cloud state.
#
# Usage:
#   scripts/run-report.sh benchmark acme_aws_reporting.benchmark.custom_baseline prod
#   scripts/run-report.sh benchmark acme_aws_reporting.benchmark.custom_baseline all
#   scripts/run-report.sh dashboard acme_aws_reporting.dashboard.account_overview dev
#
# Requires: powerpipe, steampipe (service running or auto-started), and the
# aws_<env> connections + an aggregator from the steampipe skill's aws.spc.

set -euo pipefail

KIND="${1:?kind required: benchmark | dashboard}"
RESOURCE="${2:?resource required, e.g. acme_aws_reporting.benchmark.custom_baseline}"
TARGET="${3:?environment required: dev | staging | prod | all}"

# Output format differs by kind: benchmarks -> asff+json+html, dashboards -> html/pps.
case "$KIND" in
  benchmark) FORMATS=(html asff json) ;;
  dashboard) FORMATS=(html pps) ;;
  *) echo "kind must be 'benchmark' or 'dashboard'" >&2; exit 2 ;;
esac

# Expand "all" into the concrete env list (keep in sync with aws.spc).
if [ "$TARGET" = "all" ]; then
  ENVS=(dev staging prod)
else
  ENVS=("$TARGET")
fi

DATE="$(date +%Y-%m-%d)"
SHORT="${RESOURCE##*.}"   # last segment, e.g. custom_baseline

for env in "${ENVS[@]}"; do
  outdir="out/${env}"
  mkdir -p "$outdir"
  for fmt in "${FORMATS[@]}"; do
    out="${outdir}/${SHORT}-${DATE}.${fmt}"
    echo ">> ${KIND} ${RESOURCE}  env=${env}  fmt=${fmt}  ->  ${out}"
    powerpipe "$KIND" run "$RESOURCE" \
      --search-path-prefix "aws_${env}" \
      --output "$fmt" > "$out"
  done
done

echo "Done. Artifacts under out/"
