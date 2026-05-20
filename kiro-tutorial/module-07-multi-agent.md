# Module 7 — Multi-agent and Subagents

**Part 2 / kiro-cli Primitives** &middot; ~15 min read &middot; prereq: Module 6

> One agent can do a lot. But when a task fans out — parallel investigations, isolated dangerous operations, multi-perspective reviews — you want more than one. kiro-cli's `subagent` tool lets a parent agent spawn child agents with their own configs, each fully scoped. **There is no `/spawn` command.** This happens inside the loop.

---

## 7.1 — The `subagent` tool

Clear this up first: **there is no `/spawn` slash command in kiro-cli.** Subagent spawning is a tool call the LLM makes, just like `fs_read` or `execute_bash`. From the LLM's perspective:

```json
{
  "tool": "subagent",
  "input": {
    "agent": "code-reviewer",
    "prompt": "Review the changes in src/auth/"
  }
}
```

The harness sees this, spins up a new kiro-cli runtime configured as `code-reviewer`, runs it with the given prompt, captures its final response, and returns that to the parent as the tool result. The parent continues with that result in context.

> A subagent is a recursive kiro-cli session, scoped to a child agent config, with the result piped back to the parent.

---

## 7.2 — Anatomy of an orchestrator

The parent (orchestrator) is a regular agent with the `subagent` tool enabled and an `availableAgents` whitelist:

```json
{
  "name": "review-orchestrator",
  "description": "Coordinate a multi-perspective review",
  "model": "claude-sonnet-4",
  "prompt": "You coordinate reviews. For a given MR, spawn a code-reviewer subagent for code quality, a security-reviewer for security, and a doc-reviewer for docs. Combine findings into one report. You don't read files directly — delegate.",
  "tools": ["subagent"],
  "availableAgents": ["code-reviewer", "security-reviewer", "doc-reviewer"],
  "trustedAgents": ["doc-reviewer"]
}
```

Three new fields:

- `tools: ["subagent"]` — the parent has only this tool. It can delegate but not act directly. (Add `fs_read` if it should read for context.)
- `availableAgents` — whitelist of child agents this parent may spawn
- `trustedAgents` — subset that skip the permission prompt when spawned

---

## 7.3 — The orchestrator pattern

The pattern that's most useful in practice:

- **Parent: read-only or no-fs.** It plans, delegates, summarises. Cheap model (Haiku) often suffices.
- **Children: scoped writers or investigators.** Each has its own allowed tools, MCP servers, and file boundaries.

What you gain:

- **Bounded blast radius** — only children can write, each in its own scope
- **Parallelism** — parent can spawn independent children concurrently
- **Token efficiency** — children's full reasoning doesn't pollute parent context; only their final output returns

---

## 7.4 — DAG planning

The model can think of subagent invocations as a DAG:

```
            review-orchestrator
                    |
        +-----------+-----------+
        |           |           |
   code-rev     sec-rev     doc-rev
                    |
                synthesise
```

The parent decides which children are independent (parallel) and which have dependencies (sequential). It composes the result at the end. **Fork/join applied to LLM workflows.** The parent is the join point.

---

## 7.5 — What subagents CAN'T do

Constraints to internalise before you architect around subagents:

| Constraint | Implication |
|---|---|
| **Hooks don't fire on subagents** | If you rely on a `preToolUse` hook to block prod writes, that hook only runs on the main agent. Subagent writes are **not** gated by hooks. Lock down at the agent config instead. |
| **Typically no MCP / web tools in subagents** | Many MCP servers can't be safely shared; subagents often run without them. Verify per-server before assuming. |
| **No nested orchestration by default** | A subagent typically cannot spawn its own subagents (or only one level, depending on config). |
| **Their context is fresh** | A subagent does **not** see the parent's conversation. You must pass everything it needs in the prompt. |
| **You only get the final response** | The parent doesn't see the subagent's tool calls, intermediate reasoning, or files read. Just the final text. |

The last two combined matter most: **the prompt to a subagent is a complete brief, not a conversation.**

---

## 7.6 — Inspecting subagents at runtime

In the TUI, press **`Ctrl+G`** to open the subagent monitor — see spawned children, their status, their progress reports. Useful when an orchestration is opaque from outside.

---

## 7.7 — When NOT to use subagents

| Situation | Better alternative |
|---|---|
| Single linear task | One agent |
| Task needs fine-grained hook enforcement | Main agent (hooks don't fire on subs) |
| You want to see every step turn-by-turn | Main agent (subagents are opaque between start/finish) |
| All operations share the same trust level | One scoped agent |

Subagents shine when you have **parallelism + scope isolation** as joint requirements. If you have only one of those, simpler structures work.

---

## 7.8 — A concrete fan-out

User runs:

```bash
kiro-cli --agent review-orchestrator "Review MR !1234"
```

Inside the loop:

1. Parent calls `subagent(code-reviewer, "Review src/ changes in branch X")` &rarr; waits
2. Parent calls `subagent(security-reviewer, "Audit IAM changes in branch X")` &rarr; waits
3. Parent calls `subagent(doc-reviewer, "Check docs match changes in branch X")` &rarr; waits
4. Parent receives three markdown reports
5. Parent synthesises into one final report

If the parent is smart and the harness supports it, calls 1-3 can run in parallel. The whole orchestration completes in roughly `max(child durations)` instead of `sum`.

---

## Mini-exercise

Write an orchestrator with two child agents:

- `lint-checker` — only `execute_bash` with `ruff *` and `mypy *`
- `test-runner` — only `execute_bash` with `pytest *`

Orchestrator prompt:

```
Run linting and tests in parallel. Combine results.
If either failed, report which checks failed and the first 3 errors from each.
```

Run on your repo. Confirm via `/agent` and `/tools` that the orchestrator can only use `subagent`, and that the children have only their scoped tools.

---

## Check yourself

| # | Claim | Answer |
|---|---|---|
| 1 | I spawn a subagent by typing `/spawn` in the TUI. | **False.** There is no `/spawn` command. Subagent is a tool the LLM calls inside the loop. |
| 2 | A `preToolUse` hook on the parent blocks subagent file writes. | **False.** Hooks don't fire for subagents. Use the subagent's own config to restrict. |
| 3 | A subagent inherits the parent's conversation history. | **False.** Subagents start with a fresh context; the parent's prompt must contain everything they need. |
| 4 | The parent sees every tool call the subagent makes. | **False.** The parent receives only the subagent's final response. Use `Ctrl+G` to inspect during execution. |

---

## What's next

**Module 8 — Hooks.** Where steering is advisory and agents are scoped, hooks are the *mechanical enforcement* layer. Bash that runs at lifecycle events. The only way to actually **block** an action the LLM proposes.
