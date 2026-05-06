<!-- Install to: ~/.kiro/prompts/  OR  <project>/.kiro/prompts/ -->
<!-- Invoke as: @new-terraform-module -->

Scaffold a new reusable Terraform module following our conventions.

Ask me first (one question at a time):
1. Module name (kebab-case, mirrors the AWS noun — e.g. `lambda-with-sqs`).
2. The AWS resources it wraps (top-level only — sub-modules later).
3. Target path (default: `modules/<name>/` in the current repo).

Then generate exactly this layout under the target path:

```
<name>/
  main.tf       resources only, no providers
  variables.tf  every input has description + type + (where useful) validation
  outputs.tf    every output has description
  versions.tf   terraform >= 1.7, AWS provider >= 5.0
  README.md     purpose, inputs/outputs table, one usage example
  examples/
    minimal/
      main.tf       smallest possible call site
      versions.tf
```

Conventions to apply:
- Resource names mirror the AWS noun (`aws_lambda_function "this"` for a
  single-resource module; descriptive names when there are several).
- No `provider` blocks inside the module.
- Required tags: `Project`, `Environment`, `Owner`, `ManagedBy`, `Repo`,
  `CostCenter` — accept a `tags` input that merges with module-internal tags.
- No hardcoded ARNs, account IDs, or regions.

After generating, print the README's usage block and remind me to add the
module to whatever change-log / module index the repo uses (ask me where).
