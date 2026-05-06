# Project layout

The single-environment standard. Every root module looks like this:

```
.
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf       # terraform + provider version pins
├── providers.tf      # provider configuration, default_tags, aliases
├── data.tf           # data sources (caller_identity, AMIs, hosted zones)
├── locals.tf         # naming, derived maps
├── terraform.tfvars  # gitignored when it contains environment values
└── modules/
    └── <name>/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── versions.tf
        └── README.md
```

## When to split files

One giant `main.tf` is fine for a tutorial and wrong for anything else. Once a root module has more than ~150 lines, split by AWS service domain: `iam.tf`, `vpc.tf`, `s3.tf`, `kms.tf`, `rds.tf`. The split is purely organizational — Terraform concatenates all `.tf` files in a directory before parsing, so file names have no semantic meaning. Use this freedom to make code reviewable.

## When to extract a module

Split by file when the resources still belong to one logical stack. Split into a `modules/` subdirectory when there is a reusable unit (a network, a service, a cluster).

Three rules for when to make a module:

1. **Repeated three times or more.** First time, write inline. Second time, copy. Third time, refactor into a module. Premature module-ization causes more pain than it saves.
2. **Represents a logical unit.** A VPC, an ECS service, an EKS cluster, a "standard S3 bucket" with all the security controls. These are real abstractions worth a module even on first use.
3. **NOT a trivial wrapper.** A module that takes the same inputs as `aws_s3_bucket` and just passes them through is a tax, not an abstraction.

## Composition over nesting

Three levels of module nesting (root → wrapper → component → primitive) is the limit before debugging becomes painful. Prefer composition: the root calls multiple flat modules and wires their outputs together, rather than one mega-module that wraps everything.

For multi-account orchestration, environment-per-folder layouts, and DRY composition across stacks, see the `terragrunt-multi-account` skill instead of nesting Terraform modules deeper.
