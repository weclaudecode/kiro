# Module 12 — Operating Surface

**Part 3 / Patterns and Discipline** &middot; ~9 min read &middot; prereq: Module 11

> The TUI commands, the headless CLI, the auth model, the tier gotchas. Below the abstractions of Parts 1 and 2 sits the actual surface you operate. This module is a reference; skim once, return when needed.

---

## 12.1 — Interactive slash commands

| Command | What it does |
|---|---|
| `/agent` | List agents; switch with `/agent <name>` |
| `/context` | Show what's currently in context: steering, resources, token counts |
| `/tools` | Show available tools for this session |
| `/mcp` | List connected MCP servers and their tools |
| `/clear` | Wipe conversation history, keep agent + steering |
| `/compact` | Summarise history to reduce tokens (lossy) |
| `/resume` | Reload a previous session (where supported) |
| `/help` | List commands |

Habit: `/context` early and often. Most "the agent isn't behaving" issues are visible there.

---

## 12.2 — Headless mode

For CI/CD, scripts, and automation:

```bash
kiro-cli --no-interactive --agent code-reviewer "Review the diff in MR !1234"
```

Headless mode:

- No TUI; output to stdout
- Exit code reflects success/failure
- Subagents and hooks still run
- Permissions: typically denies any tool that would prompt for confirmation; either pre-approve via `trustedAgents` / config, or use the `--auto-approve` flag (treat carefully)

GitLab CI example:

```yaml
agent-review:
  stage: test
  image: ${KIRO_CLI_IMAGE}
  variables:
    KIRO_API_KEY: $KIRO_API_KEY
  script:
    - kiro-cli --no-interactive --agent code-reviewer
              "Review the diff between $CI_MERGE_REQUEST_DIFF_BASE_SHA and HEAD.
               Output markdown to stdout."
              > review.md
  artifacts:
    paths: [review.md]
```

This is roughly the agent-platform pattern, with a runner that has the `gitlab--duo` tag and a `KIRO_API_KEY` from CI variables.

---

## 12.3 — Auth and configuration

| Concern | Setting |
|---|---|
| Auth | `KIRO_API_KEY` env var (or AWS SSO-backed) |
| Region | `AWS_REGION` if using Bedrock-backed models |
| Config root | `~/.aws/kiro-cli/` (global) and `.kiro/` (workspace) |
| Logging | `~/.aws/kiro-cli/logs/` — useful when debugging tool calls |

For team setups: store the API key in your secrets manager, inject as CI variable for pipelines, use SSO locally.

---

## 12.4 — Tier gotchas

A few practical realities of using kiro-cli at scale:

- **Rate limits** apply per account/tier — burst usage in CI can throttle
- **Model availability** varies; some agents may not support all models on all tiers
- **Credits** consume against your plan; track usage especially for fan-out orchestrations
- **Runner tag** `gitlab--duo` is required for the GitLab agent platform integration
- **Version pinning** — kiro-cli evolves quickly; pin a version in CI containers, upgrade deliberately

When something stops working between minor versions, check the changelog before debugging your config.

---

## 12.5 — Editor integration

kiro-cli ships standalone, but Kiro IDE (or the editor companion plugin) gives a richer surface — inline suggestions, MR-attached reviews, in-editor steering edits. **The configs are the same.** Whatever lives in `.kiro/` works in both surfaces.

If your team uses VS Code, look for the Kiro plugin. Same primitives, different ergonomics.

---

## 12.6 — Diagnostic patterns

When an agent misbehaves:

1. `/context` — is the rule loaded?
2. `/tools` — does the agent have the tools it needs?
3. `/mcp` — are MCP servers connected?
4. Check logs in `~/.aws/kiro-cli/logs/`
5. Reproduce with a minimal prompt to isolate

When CI runs misbehave:

1. Run the same command headless on your laptop
2. Compare env vars; `KIRO_API_KEY`, `AWS_REGION` set in CI?
3. Check the runner has the `gitlab--duo` tag and image has kiro-cli installed
4. Hooks: are they executable in the CI container?

---

## Check yourself

| # | Claim | Answer |
|---|---|---|
| 1 | Headless mode disables hooks and subagents. | **False.** Both run. Permissions may differ. |
| 2 | `/clear` deletes my steering files. | **False.** It clears conversation history. Steering files on disk are untouched. |
| 3 | I should commit `KIRO_API_KEY` to the repo for team sharing. | **False.** Use CI secrets / secrets manager. Never commit keys. |
| 4 | The IDE plugin and the CLI use different configs. | **False.** Same <code>.kiro/</code> dir. Same primitives. |

---

## What's next

**Module 13 — Best Practices.** The patterns that distinguish teams who get value from kiro-cli from teams who fight it. Also: the LICENSE gotcha you need to know about.
