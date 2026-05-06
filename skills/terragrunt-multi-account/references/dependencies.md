# Dependencies Between Stacks

Terragrunt models inter-unit dependencies natively. This is strictly better
than `terraform_remote_state` data sources because it gives Terragrunt the
dependency graph, enabling correct `run-all` ordering and parallelism.

## Example

```hcl
# live/prod/us-east-1/eks/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-0000000000000000a", "subnet-0000000000000000b"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "kms" {
  config_path  = "../../kms"
  skip_outputs = false
}

terraform {
  source = "git::ssh://git@github.com/acme/terraform-modules.git//eks?ref=v2.1.0"
}

inputs = {
  cluster_name       = "prod-use1"
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
  kms_key_arn        = dependency.kms.outputs.key_arn
}
```

## Rules

- **`dependency` reads the dep's outputs at plan/apply time.** Terragrunt
  runs `terraform output` in the dep before processing the dependent unit.
- **`mock_outputs`** lets validate/plan run on a fresh checkout (CI on a
  feature branch) before the dep exists. Always guard with
  `mock_outputs_allowed_terraform_commands` to prevent mocks reaching
  `apply`. Never include `apply` in that list.
- **`skip_outputs = true`** for ordering-only dependencies — the unit must
  run after the dep but does not consume its outputs (e.g., a CloudTrail
  unit that needs the logs bucket to exist but reads its name from a
  separate locals file).
- **Why this is better than `terraform_remote_state` data sources.** The
  data-source approach hides the graph from Terragrunt, so `run-all` cannot
  order correctly and engineers must `apply` units manually in the right
  order. With `dependency`, the graph is explicit and Terragrunt can run in
  parallel across independent branches.

## `mock_outputs_merge_strategy_with_state`

When the dep already has state, Terragrunt prefers the real outputs over
mocks. The strategy controls how mock fallback fills any gaps:

- `no_merge` (default): use real outputs verbatim.
- `shallow`: top-level keys missing from real outputs come from mocks.
- `deep_map_only`: deep merge for map-typed outputs.

`shallow` is the right default when the module gains new outputs that the
state predates. Without it, plan-time errors appear after a module bump
until the dep is reapplied.

## `dependencies` block (ordering only)

For pure ordering with no output access:

```hcl
dependencies {
  paths = ["../iam-baseline", "../kms"]
}
```

Use sparingly. Prefer `dependency` blocks even with `skip_outputs = true` —
the result is more explicit and easier to audit.

## Visualising the graph

```
terragrunt graph-dependencies | dot -Tsvg > graph.svg
```

Run from the live root. The output is a fast sanity check before any
`run-all apply`: any dependency mistake or accidental cycle will surface.
