# EKS Troubleshooting Playbook (read-only)

Every command here is GET-class — it never mutates the cluster. Work from
the symptom down to a quoted piece of evidence before proposing a fix.

## First three commands, always

```bash
kubectl config current-context                                   # am I on the right cluster?
kubectl get pods -A --field-selector=status.phase!=Running       # what's unhealthy
kubectl get events -A --sort-by=.lastTimestamp | tail -40        # what just happened
```

Then drill into one object:

```bash
kubectl describe pod <pod> -n <ns>          # Events + Last State + exit code
kubectl logs <pod> -n <ns> --previous        # the crash, not the restart
kubectl get pod <pod> -n <ns> -o yaml        # status.conditions, ownerReferences
```

## Exit-code / state decoder

| Signal | Meaning | Likely cause | Confirm with |
|---|---|---|---|
| Exit 137 / `OOMKilled` | Killed by the kernel OOM | memory limit too low, or a leak | `describe` → Last State; `kubectl top pod` |
| Exit 1 / `Error`, `CrashLoopBackOff` | App died on startup | bad config, missing dep, code error | `logs --previous` |
| `ImagePullBackOff` / `ErrImagePull` | Can't pull the image | wrong tag, private registry auth, ECR + IRSA perms | `describe` → Events; image ref; pull secret |
| `CreateContainerConfigError` | Container can't be configured | missing ConfigMap/Secret key referenced in env/volume | `describe` → Events |
| `Pending` / `Unschedulable` | Scheduler can't place it | insufficient cpu/mem, taints w/o tolerations, affinity, unbound PVC, autoscaler maxed | `describe` → Events (FailedScheduling) |
| `RunContainerError` | Runtime refused to start it | bad command/entrypoint, volume mount issue | `describe`; `logs` |
| Readiness failing, 0 endpoints | Probe never passes | wrong probe path/port, slow boot, downstream dep down | `describe` probe config; `logs` |
| Node `NotReady` | kubelet/node unhealthy | disk/memory pressure, network, AMI/kubelet | `kubectl describe node <n>` → Conditions |

## Scenario walkthroughs

### CrashLoopBackOff
1. `kubectl logs <pod> -n <ns> --previous` — the crashed container's last
   output. This is where the real error is.
2. `kubectl describe pod` — Events (image, mounts) and restart count.
3. Tie the error to the image/config: a new image tag (regression) or a
   changed ConfigMap/Secret. Compare to the last good revision in git.

### ImagePullBackOff on EKS
1. `describe` → exact registry error.
2. Is the tag/digest real? `aws ecr describe-images` (read-only) for ECR.
3. For ECR: the **node role** (not IRSA) needs
   `AmazonEC2ContainerRegistryReadOnly`; for cross-account, the repo
   policy must allow the pulling account. For private non-ECR registries,
   check the `imagePullSecrets`.

### Pending / Unschedulable
1. `describe` → `FailedScheduling` message names the constraint.
2. Resources: requested cpu/mem vs node capacity (`kubectl top node`,
   `kubectl describe node`). Cluster Autoscaler / Karpenter at max?
3. Taints vs tolerations; nodeAffinity / topologySpread.
4. PVC unbound? `kubectl get pvc -n <ns>` and the StorageClass.

### OOMKilled (exit 137)
1. `describe` → Last State `OOMKilled`.
2. `kubectl top pod` for the live trend.
3. Decide: limit genuinely too low (raise it) vs a leak (fix the app —
   raising the limit just delays the kill).

### IRSA / AWS access denied from a pod
1. `kubectl get sa <sa> -n <ns> -o yaml` → must have annotation
   `eks.amazonaws.com/role-arn: arn:aws:iam::<acct>:role/<role>`.
2. The pod must actually use that SA (`spec.serviceAccountName`).
3. The IAM role's **trust policy** must allow the cluster OIDC provider
   with a `sub` condition
   `system:serviceaccount:<ns>:<sa>`.
4. The role's permission policy must allow the API the app calls. See
   `irsa-and-security.md`.

## AWS-side correlation (read-only)

- **EKS MCP server** / `aws eks describe-cluster|describe-nodegroup` —
  cluster + node group health, version skew.
- **CloudWatch MCP server** — Container Insights metrics and application
  log groups when pod logs have already rotated.
- **Load balancer**: a failing Ingress/Service of type LoadBalancer →
  check the AWS Load Balancer Controller logs and the target group health
  in EC2.

## What NOT to do (this is a diagnosis, not a remediation)

No `apply`, `delete`, `edit`, `patch`, `scale`, `rollout restart`,
`cordon`, `drain`, or `exec`. Propose the fix as a manifest/IAM change and
let it go through git + Argo/Flux.
