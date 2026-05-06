# Steering Files Guide

Steering files (`*.md` in `~/.kiro/steering/` or `<project>/.kiro/steering/`)
are kiro's equivalent of Claude Code's `CLAUDE.md`. Each file is
Markdown with optional YAML frontmatter that controls when kiro loads it
into the conversation.

## Inclusion modes

```yaml
---
inclusion: always         # default — load every interaction
---
```

```yaml
---
inclusion: fileMatch
fileMatchPattern: "**/*.py"
---
```

Multiple patterns:

```yaml
---
inclusion: fileMatch
fileMatchPattern:
  - "**/handler.py"
  - "**/lambda_function.py"
---
```

```yaml
---
inclusion: manual         # only when invoked as /<filename-without-ext>
---
```

```yaml
---
inclusion: auto           # description-matched, like a skill
description: "When working on caching policy or CDN configuration"
---
```

## When to use which

| Mode | Use for |
|---|---|
| `always` | Cross-cutting rules every session must respect — security, secrets, tech-stack defaults, branching workflow |
| `fileMatch` | Language- or filetype-specific conventions (Python, Terraform, GitLab CI) — irrelevant outside that file scope |
| `manual` | Reference docs you want to pull in deliberately, e.g. `/postmortem-template`, `/onboarding` |
| `auto` | Specialized contexts that are hard to detect from filename alone — let kiro's matcher decide |

## What goes inside

A good steering file:

- States rules in the imperative ("never commit secrets", "use Powertools").
- Gives **why** for non-obvious rules so the model can judge edge cases.
- Lists explicit anti-patterns ("things to avoid"), not just patterns.
- Stays under ~100 lines. If it grows past that, split by topic.
- Avoids restating the obvious (don't list "use type hints" three times
  across three files).

## What NOT to put in steering

- Project state ("we're migrating from X to Y this quarter") — that's
  a project memory or a spec, not a rule.
- Code samples longer than ~30 lines — link to a skill or template.
- Anything that changes per repo when the file is in `~/.kiro/steering/`
  global. Per-repo specifics go in `<project>/.kiro/steering/`.

## Reference: precedence

Workspace `.kiro/steering/` overrides global `~/.kiro/steering/` on file
name conflicts. Both can coexist when names differ.

## See also

- Catalog steering files: `../steering/`
- Kiro CLI docs: <https://kiro.dev/docs/cli/steering/>
