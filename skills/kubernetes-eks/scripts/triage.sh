#!/usr/bin/env bash
# triage.sh — read-only EKS/Kubernetes health snapshot.
# GET-class only: never applies, deletes, scales, patches, or execs.
# Safe to run against any cluster you can read. Pipe the output into a
# headless kiro agent for diagnosis, e.g.:
#   skills/kubernetes-eks/scripts/triage.sh | \
#     kiro-cli chat --no-interactive --agent eks-troubleshooter \
#       --trust-tools=read "Triage this snapshot."
#
# Usage: triage.sh [namespace]   (omit namespace for cluster-wide)

set -euo pipefail

NS="${1:-}"
if [[ -n "$NS" ]]; then
  SCOPE=(-n "$NS"); LABEL="namespace=$NS"; RCOL=4   # NAME READY STATUS RESTARTS AGE
else
  SCOPE=(-A);       LABEL="all namespaces"; RCOL=5   # NAMESPACE NAME READY STATUS RESTARTS AGE
fi

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found on PATH" >&2; exit 127; }

section() { printf '\n===== %s =====\n' "$1"; }

section "context"
kubectl config current-context 2>/dev/null || echo "(no current context)"
kubectl version --output=json 2>/dev/null | grep -E '"gitVersion"' | head -2 || true
echo "scope: $LABEL"

section "pods not Running"
kubectl get pods "${SCOPE[@]}" --field-selector=status.phase!=Running 2>/dev/null || true

section "recent Warning events (last 40)"
kubectl get events "${SCOPE[@]}" --field-selector type=Warning \
  --sort-by=.lastTimestamp 2>/dev/null | tail -40 || true

section "restart hotspots (pods with restarts)"
# RESTARTS column position depends on scope: $5 under -A (leading NAMESPACE),
# $4 under -n. The column may read like "5 (3h ago)"; $RCOL+0 coerces the count.
kubectl get pods "${SCOPE[@]}" --no-headers 2>/dev/null \
  | awk -v c="$RCOL" '$c+0 > 0 {print}' || true

section "node conditions"
kubectl get nodes -o wide 2>/dev/null || true
kubectl describe nodes 2>/dev/null \
  | grep -E 'Name:|MemoryPressure|DiskPressure|PIDPressure|Ready' | head -40 || true

section "top consumers (best-effort; needs metrics-server)"
kubectl top pods "${SCOPE[@]}" 2>/dev/null | sort -k3 -h -r | head -15 || echo "(metrics-server unavailable)"
kubectl top nodes 2>/dev/null || true

echo
echo "(read-only snapshot complete — no cluster state was modified)"
