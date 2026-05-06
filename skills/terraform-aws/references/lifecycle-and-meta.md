# Lifecycle and meta-arguments

## `create_before_destroy`

For replacement-sensitive resources, force the new one to exist before the old is destroyed:

```hcl
resource "aws_launch_template" "app" {
  name_prefix = "${local.name_prefix}-app-"
  # ...

  lifecycle {
    create_before_destroy = true
  }
}
```

Required for: ASG launch templates (so the ASG can shift), IAM policies attached to live roles (so attachment never points at a dead policy), Route53 records during a rename, ALB listeners.

## `prevent_destroy`

For stateful resources where accidental destroy is catastrophic:

```hcl
resource "aws_db_instance" "primary" {
  # ...

  lifecycle {
    prevent_destroy = true
  }
}
```

Foot-gun: when intentionally retiring the resource, the `prevent_destroy = true` line must be removed first, then `terraform apply`, then a second `apply` to actually destroy. Plan failure with "this resource cannot be destroyed" is the guard working as intended.

## `ignore_changes`

For fields legitimately modified outside Terraform:

```hcl
resource "aws_autoscaling_group" "app" {
  # ...

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_ecs_service" "app" {
  # ...

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}
```

Common: ASG `desired_capacity` (managed by autoscaling policies), ECS `desired_count` and `task_definition` (managed by deploy tool), tag keys added by AWS Config or Backup.

Never use `ignore_changes = ["*"]` or `ignore_changes = all`. That is a confession that no one understands what the resource does.

## `depends_on`

Should be rare. Real attribute references (`aws_subnet.foo.id`) create implicit dependencies that Terraform tracks correctly. Use explicit `depends_on` only when the dependency is invisible at the attribute level — e.g., an IAM policy that grants permissions used at resource creation time but is not referenced by ARN.

## `moved` blocks

Refactor without destroy/recreate. Renaming a resource or moving it into a module:

```hcl
moved {
  from = aws_instance.app
  to   = module.compute.aws_instance.app
}
```

After the next apply, the `moved` block can be removed. This replaces the legacy `terraform state mv` workflow for in-code refactors.

## `import` blocks (TF 1.5+)

Code-reviewable imports:

```hcl
import {
  to = aws_iam_role.legacy
  id = "legacy-app-role"
}

resource "aws_iam_role" "legacy" {
  name               = "legacy-app-role"
  assume_role_policy = data.aws_iam_policy_document.legacy_assume.json
}
```

Plan shows the import; apply executes it. PR reviewers see what was imported. Far better than running `terraform import` from a developer laptop with no audit trail.

## `removed` blocks (TF 1.7+)

Drop a resource from state without destroying the underlying AWS resource:

```hcl
removed {
  from = aws_iam_role.deprecated

  lifecycle {
    destroy = false
  }
}
```

Useful when handing a resource over to another stack or to manual ownership.

## Drift management

`terraform plan` prints three signals: create (`+`), update in place (`~`), replace (`-/+`). Read replacements carefully — the line annotated `# forces replacement` names the field that triggered it.

`terraform plan -refresh-only` reads current AWS state and shows drift without proposing changes. Run this after suspicious incidents (a console click, a runbook action) to see exactly what diverged.

When drift is found:

1. **The console change was correct** — fold it into Terraform code, run `terraform apply` (no-op against the now-correct world).
2. **The console change was wrong** — `terraform apply` reverts it. Tell whoever made the change.
3. **The field is legitimately externally managed** — add it to `lifecycle.ignore_changes`.

For renaming, use a `moved` block. For removing from state without destroying, use a `removed` block. For pulling in a resource AWS already owns, use an `import` block. The CLI commands `terraform state mv`, `terraform state rm`, and `terraform import` still work but bypass code review — prefer the block forms.

Before any `terraform state rm` or `terraform state mv`: take a state backup (`terraform state pull > backup.tfstate`) and confirm the lock table shows your lock.
