# Module 8 — Hooks

**Part 2 / kiro-cli Primitives** &middot; ~11 min read &middot; prereq: Module 7

> Steering is advisory. Agents are scoped. Hooks are *mechanical enforcement*. They are bash (or any executable) that runs at lifecycle events. If you need to **actually block** an action — not just ask the LLM nicely — you need a hook.

---

## 8.1 — The lifecycle

kiro-cli fires events around the agent loop. Hooks are scripts you register against these events.

| Event | When it fires | Can it block? |
|---|---|---|
| `agentSpawn` | A session/agent starts | No (initialisation only) |
| `userPromptSubmit` | The user submits a prompt | Yes (exit non-zero to reject) |
| `preToolUse` | The LLM is about to call a tool | **Yes** (exit code 2 blocks the call) |
| `postToolUse` | A tool has returned | No (side effects only) |
| `stop` | The agent is about to return final text | Yes (can force another turn) |

> `preToolUse` exit code `2` is the only mechanism that **stops the LLM from doing something**. Everything else either prepares or observes.

---

## 8.2 — Where hooks live

Workspace-scoped, committed with the repo:

```
.kiro/hooks/
├── pre-tool-use.sh
├── post-tool-use.sh
└── stop.sh
```

Each script receives event data on stdin (JSON) and can return JSON on stdout to influence behavior. Exit code matters per event (see table above).

---

## 8.3 — Anatomy: block writes to infra/prod

`.kiro/hooks/pre-tool-use.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Read event payload from stdin
event=$(cat)

tool=$(echo "$event" | jq -r '.tool')
path=$(echo "$event" | jq -r '.input.path // empty')

# Block fs_write or execute_bash that touches infra/prod/
if [[ "$tool" == "fs_write" && "$path" == infra/prod/* ]]; then
  echo '{"reason": "Direct writes to infra/prod/ are blocked. Use the prod-deploy spec."}'
  exit 2   # exit 2 = block the tool call
fi

exit 0   # allow
```

Make it executable. From now on, any attempt by the LLM to write under `infra/prod/` is hard-blocked. The model sees the rejection reason and adapts (typically by asking the user or proposing a different path).

---

## 8.4 — Hooks vs steering vs agent config

| Mechanism | Strength | Weakness |
|---|---|---|
| Steering | Easy to write; advisory | LLM can ignore it |
| Agent config (tools / allowedPaths) | Enforced by harness; declarative | Coarse-grained; one config per session |
| **Hooks** | Programmatic; can inspect content; can block at exact decision points | Operational overhead; needs bash + jq skill in the team |

Use hooks when you need **content-aware** enforcement — e.g., "block fs_write to files containing the literal `secret=`" — which neither steering nor static config can express.

---

## 8.5 — Useful hook patterns

| Pattern | Event | What it does |
|---|---|---|
| Lint after edit | `postToolUse` (on `fs_write`) | Run `ruff` / `mypy`; surface errors to next turn |
| Block prod writes | `preToolUse` (on `fs_write`) | Reject if path matches prod patterns |
| Audit log | `postToolUse` (any) | Append tool name + path + diff hash to a log file |
| Stop confirmation | `stop` | Require the agent to summarise what it changed before exiting |
| Prompt injection guard | `userPromptSubmit` | Reject prompts that contain suspicious patterns (rare in practice) |

---

## 8.6 — Hooks only fire on the main agent

This was the trap from Module 7 — worth repeating because people miss it:

> **Hooks do not fire on subagents.** If subagent enforcement matters, do it via the subagent's own config (tools whitelist, allowedPaths, prompt).

If you need belt-and-braces enforcement, combine:

- Hook on parent (blocks main-agent dangerous tool use)
- Restrictive agent config on each child (blocks the same things at the runtime level)

Both layers fail closed independently.

---

## 8.7 — Common failure modes

| Failure | Cause | Fix |
|---|---|---|
| Hook doesn't fire | Wrong filename / not executable | `chmod +x`; check event names; check `.kiro/hooks/` location |
| Hook silently allows everything | Exit code path through `0` even on rejection | Use `set -euo pipefail`; explicit `exit 2` for blocks |
| Hook breaks all tool use | Shell error → non-zero exit interpreted as block | Test the hook with a sample event payload before committing |
| Surprising subagent behavior | Hook on parent doesn't apply to children | Add equivalent restriction to subagent config |

---

## Mini-exercise

Write a `preToolUse` hook that blocks any `fs_write` to a path containing `.env`:

```bash
#!/usr/bin/env bash
event=$(cat)
tool=$(echo "$event" | jq -r '.tool')
path=$(echo "$event" | jq -r '.input.path // empty')

if [[ "$tool" == "fs_write" && "$path" == *.env* ]]; then
  echo '{"reason": ".env files contain secrets. Edit manually."}'
  exit 2
fi
exit 0
```

Test it by asking the agent: *"Update .env.local to add a new variable."* Confirm the rejection is surfaced cleanly.

---

## Check yourself

| # | Claim | Answer |
|---|---|---|
| 1 | A `postToolUse` hook can block a tool call. | **False.** It runs *after*. Use `preToolUse` with exit code 2 to block. |
| 2 | Hooks apply to subagents the same as the main agent. | **False.** Hooks fire only on the main agent. |
| 3 | Steering can replace hooks for hard rules. | **False.** Steering is advisory. Hooks enforce mechanically. |
| 4 | Hooks must be bash. | **False.** Any executable works — Python, Node, Go binary. Bash + jq is just the common pattern. |

---

## What's next

**Module 9 — Specs.** The last primitive. For non-trivial work where you want human review at each phase, specs give you a multi-document, gated build: requirements → design → tasks. EARS notation makes the requirements precise enough that even a non-deterministic agent can implement them reliably.
