<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern: ["k8s/**/*.yaml", "k8s/**/*.yml", "**/*.k8s.yaml", "**/kustomization.yaml", "**/templates/**/*.yaml", "**/values*.yaml"]
---

# Kubernetes / EKS Conventions

Applies to Kubernetes manifests, Kustomize overlays, and Helm charts.
Cluster platform is **Amazon EKS**; assume IRSA (IAM Roles for Service
Accounts) for any pod that touches AWS.

## Workloads
- Every container sets `resources.requests` **and** `resources.limits`
  (cpu + memory). No unbounded pods — they break bin-packing and the
  cluster autoscaler.
- Set `readinessProbe` and `livenessProbe`; never let traffic hit a pod
  before it's ready. Use a separate `startupProbe` for slow boots.
- `imagePullPolicy: IfNotPresent` with **digest-pinned** images
  (`repo@sha256:…`) or immutable tags — never `:latest`.
- Two+ replicas for anything user-facing, plus a `PodDisruptionBudget`.
- Spread across AZs with `topologySpreadConstraints`
  (`topologyKey: topology.kubernetes.io/zone`).

## Security (pod & cluster)
- `securityContext`: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`,
  `allowPrivilegeEscalation: false`, drop `ALL` capabilities. No
  `privileged: true`, no `hostNetwork`/`hostPID`/`hostPath` without a
  written exception.
- **AWS access via IRSA only** — a `ServiceAccount` annotated with
  `eks.amazonaws.com/role-arn`. No node-role credentials for app pods, no
  static AWS keys in Secrets/env.
- Secrets come from AWS Secrets Manager / SSM via the Secrets Store CSI
  driver or External Secrets Operator — not hand-written `Secret`
  manifests committed to git.
- Default-deny `NetworkPolicy` per namespace; open only the flows you
  need.
- Enforce a baseline with Pod Security Admission
  (`pod-security.kubernetes.io/enforce: restricted`) or a policy engine
  (Kyverno / OPA Gatekeeper).

## Naming & metadata
- Recommended labels on every object: `app.kubernetes.io/name`,
  `app.kubernetes.io/instance`, `app.kubernetes.io/part-of`,
  `app.kubernetes.io/managed-by`.
- One namespace per app+environment; never deploy to `default`.

## GitOps & delivery
- Cluster state is reconciled from git (Argo CD / Flux) — `kubectl apply`
  by hand is for break-glass only, and a human-applied change must be
  back-ported to git the same day.
- Helm values and Kustomize overlays are per-environment; no `if prod`
  branching inside templates beyond values.
- Image tags are promoted through environments by updating the manifest in
  git, not by mutating a running Deployment.

## Things to avoid
- `kubectl edit` / `kubectl patch` against prod (drifts from git).
- `latest` tags, missing resource limits, root containers — the three most
  common audit findings.
- Cluster-admin `RoleBinding`s for app service accounts. Scope RBAC to the
  namespace and verbs actually needed.
- Storing kubeconfig with long-lived tokens in CI — use
  `aws eks get-token` / OIDC.

## Troubleshooting first moves (read-only)
`kubectl get events -A --sort-by=.lastTimestamp`,
`kubectl describe pod <p>`, `kubectl logs <p> --previous`,
`kubectl get pod <p> -o yaml` (look at `status`),
`kubectl top pod/node`. Exit 137 = OOMKilled (raise memory limit or fix
leak); `ImagePullBackOff` = tag/registry/IRSA; `CrashLoopBackOff` = read
`--previous` logs.
