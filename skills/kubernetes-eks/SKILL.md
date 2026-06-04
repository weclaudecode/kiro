---
name: kubernetes-eks
description: Use when designing, deploying, securing, or debugging workloads on Amazon EKS — pod/deployment manifests, resource limits and probes, IRSA for AWS access, NetworkPolicy and Pod Security, Helm/Kustomize layout, GitOps delivery, and read-only triage of crashlooping/pending/OOMKilled pods and node pressure
---

# Kubernetes on Amazon EKS

## Overview

EKS is "Kubernetes with the AWS control plane and IAM glued on." The
things that go wrong most in real clusters are: missing resource
limits/probes, root containers, `:latest` images, and AWS access wired
through node roles or static keys instead of **IRSA**. This skill covers
production manifest design and a read-only triage playbook for the failure
modes you actually hit. It assumes the cluster is reconciled from git
(Argo CD / Flux), not `kubectl apply` by hand.

## When to Use

- Writing or reviewing a Deployment/StatefulSet/DaemonSet, a Helm chart,
  or a Kustomize overlay for EKS.
- Wiring a pod to AWS (S3, DynamoDB, SQS, Secrets Manager) the right way
  via IRSA — no static credentials.
- Hardening workloads: securityContext, NetworkPolicy, Pod Security
  Admission, RBAC scoping.
- Debugging a symptom — CrashLoopBackOff, ImagePullBackOff, Pending/
  Unschedulable, OOMKilled (exit 137), failing readiness, node NotReady.
- Deciding what belongs in git vs a break-glass `kubectl` action.

Skip for non-Kubernetes AWS architecture (use `aws-solution-architect`)
and for the Terraform that provisions the cluster/node groups (use
`terraform-aws` / `terragrunt-multi-account`).

## The workload shape

A production workload manifest is boring on purpose: explicit
`resources.requests`+`limits`, a `readinessProbe` and `livenessProbe`, a
hardened `securityContext` (`runAsNonRoot`, `readOnlyRootFilesystem`, drop
`ALL` caps), a digest-pinned image, `topologySpreadConstraints` across
zones, a `PodDisruptionBudget`, and — if it talks to AWS — a
`ServiceAccount` annotated with `eks.amazonaws.com/role-arn` (IRSA). App
pods never carry AWS keys. See the `kubernetes-conventions` steering for
the rule list this skill enforces.

## References

| File | Topic |
|---|---|
| `references/troubleshooting-playbook.md` | Symptom → cause → read-only commands for the common pod/node failures, with exit-code decoder. |
| `references/irsa-and-security.md` | IRSA end-to-end (OIDC provider, role trust policy, SA annotation), securityContext, NetworkPolicy, Pod Security Admission, RBAC scoping. |

## Scripts

| File | Purpose |
|---|---|
| `scripts/triage.sh` | Read-only cluster snapshot: non-running pods, recent warning events, node pressure, and top consumers. GET-only — never mutates. |

## Cross-references

- `aws-solution-architect` — when the question is topology/service
  selection, not workload mechanics.
- `terraform-aws` / `terragrunt-multi-account` — the IaC that creates the
  cluster, node groups, IRSA OIDC provider, and roles.
- `security-code-reviewer` — deeper manifest/IaC security review.
- `gitlab-pipeline` — OIDC auth + deploy jobs that promote images via git.

## Common Mistakes

| Mistake | Fix |
|---|---|
| No `resources.limits` | Set requests + limits; unbounded pods break scheduling |
| `image: app:latest` | Pin a digest or immutable tag |
| AWS keys in a `Secret`/env | IRSA: annotate the ServiceAccount with the role ARN |
| Container runs as root | `runAsNonRoot: true`, drop `ALL` caps, `readOnlyRootFilesystem` |
| `kubectl edit` against prod | Change git; let Argo/Flux reconcile |
| No probes | Add readiness + liveness (+ startup for slow boots) |
| Debugging by raising replicas | Read `--previous` logs and `describe` events first |
| Reading current logs after a crash | Use `kubectl logs --previous` (the crashed container) |
| cluster-admin for an app SA | Scope RBAC to the namespace and needed verbs |
| Secrets committed as manifests | External Secrets Operator / Secrets Store CSI |

## Quick Reference

| Command | Purpose |
|---|---|
| `kubectl get pods -A --field-selector=status.phase!=Running` | Everything not healthy |
| `kubectl get events -A --sort-by=.lastTimestamp` | Recent cluster events |
| `kubectl describe pod <p> -n <ns>` | Events, last state, exit code |
| `kubectl logs <p> -n <ns> --previous` | Logs from the crashed container |
| `kubectl get pod <p> -n <ns> -o yaml` | Full status/conditions |
| `kubectl top pod` / `kubectl top node` | Live CPU/memory |
| `kubectl get sa <sa> -n <ns> -o yaml` | Check IRSA role-arn annotation |
| exit 137 / OOMKilled | Memory limit too low or leak |
| `ImagePullBackOff` | Tag, registry auth, or IRSA pull perms |
| `CrashLoopBackOff` | App boot error — read `--previous` |
| `Pending`/`Unschedulable` | Resources, taints, affinity, PVC, autoscaler |
| `CreateContainerConfigError` | Missing ConfigMap/Secret key |
