# IRSA and Workload Security on EKS

## IRSA — IAM Roles for Service Accounts (the only sanctioned way a pod gets AWS access)

IRSA maps a Kubernetes ServiceAccount to an IAM role via the cluster's
OIDC provider. No static keys, no node-role sharing.

The four things that must line up:

1. **Cluster OIDC provider** exists and is registered in IAM (created once
   per cluster — Terraform: `aws_iam_openid_connect_provider` against the
   cluster's `identity.oidc.issuer`).

2. **IAM role trust policy** allows that OIDC provider, conditioned on the
   exact service account:

   ```json
   {
     "Effect": "Allow",
     "Principal": { "Federated": "arn:aws:iam::<acct>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<id>" },
     "Action": "sts:AssumeRoleWithWebIdentity",
     "Condition": {
       "StringEquals": {
         "oidc.eks.<region>.amazonaws.com/id/<id>:sub": "system:serviceaccount:<namespace>:<sa-name>",
         "oidc.eks.<region>.amazonaws.com/id/<id>:aud": "sts.amazonaws.com"
       }
     }
   }
   ```

3. **Role permission policy** — least privilege, scoped to the exact ARNs
   the app uses (see `aws-security` steering: no `Action:"*"` +
   `Resource:"*"`).

4. **ServiceAccount annotation + pod usage**:

   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: ingest
     namespace: data
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::<acct>:role/data-ingest
   ---
   # in the Pod template:
   spec:
     serviceAccountName: ingest
   ```

**Failure decoder:** `AccessDenied` despite IRSA usually means (a) the
pod doesn't reference the SA, (b) the trust policy `sub` doesn't match
`system:serviceaccount:<ns>:<sa>`, or (c) the permission policy lacks the
action. EKS Pod Identity is the newer alternative (an agent + association
instead of OIDC trust conditions) — same principle, check the association
if the cluster uses it.

## Pod hardening (securityContext)

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

Forbidden without a written exception: `privileged: true`, `hostNetwork`,
`hostPID`, `hostIPC`, `hostPath` volumes, mounting the docker socket.

## Pod Security Admission

Label namespaces to enforce the restricted baseline:

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
```

For richer policy (image registries allow-list, required labels, mutating
defaults) use **Kyverno** or **OPA Gatekeeper**.

## NetworkPolicy (default deny)

EKS needs a CNI that enforces policy (VPC CNI with network policy enabled,
or Calico/Cilium). Start default-deny per namespace, then open flows:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: data }
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

## RBAC scoping

App service accounts get a namespaced `Role`/`RoleBinding` with only the
verbs they need — never `cluster-admin`, never a `ClusterRoleBinding` for
an app SA. Audit with `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>`.

## Secrets

No hand-written `Secret` manifests in git. Pull from AWS Secrets Manager /
SSM via the **Secrets Store CSI driver** or **External Secrets Operator**,
so rotation lives in AWS and nothing secret is committed.
