# Module 10 — Context Management

**Part 3 / Patterns and Discipline** &middot; ~12 min read &middot; prereq: Part 2

> Context is the agent's working memory. It's finite. It's expensive. It decays as conversations grow. **Managing it deliberately is the single most important operational skill in agentic coding** — more than prompt-crafting, more than tool selection.

---

## 10.1 — What's in context every turn

On every model call, kiro-cli assembles a payload that typically includes:

- **System prompt** (agent-specific from the config)
- **Always-loaded steering** — `AGENTS.md` + `inclusion: always` files
- **Conditionally-loaded steering** — `fileMatch`-glob files that became relevant
- **Resources** — anything in the agent's `resources` array
- **Conversation history** — every prior user message, assistant message, tool call, tool result
- **The current user prompt**

All of this counts against the context window. Frontier models top out at ~200K tokens. By turn 50 of a real session, you can easily hit 100K+ just from accumulated history.

---

## 10.2 — Inspecting context

In the TUI:

```
/context
```

Shows what's currently loaded — steering files, resources, token counts. **Use this. Often.** Most "why is the agent ignoring my rule?" problems are revealed by `/context` showing the rule wasn't loaded.

Other useful commands (Module 12 deep-dive):

- `/tools` — what tools this session has
- `/mcp` — which MCP servers are connected
- `/compact` — summarise history to free tokens (loses fidelity)
- `/clear` — wipe conversation, keep agent + steering

---

## 10.3 — The three context budgets

Mental model: you're managing three competing budgets.

| Budget | Driven by | If you exceed |
|---|---|---|
| **Window** (~200K tokens) | Total context size | Request fails or truncates silently |
| **Cost** (latency + $) | Per-turn token count | Slow, expensive turns |
| **Signal** (attention) | Relevance of what's in context | Model loses focus, ignores rules, hallucinates |

The signal budget is the sneaky one. Even if you fit in the window, **a context full of stale tool results is noisier than a smaller, curated one.** The model attends less to instructions buried under 50K tokens of old `fs_read` output.

---

## 10.4 — Context decay strategies

Four moves, ranked by cost:

1. **`/clear`** — start fresh. Cheapest move. Keep agent + steering, drop history. Use when one task is done and the next is unrelated.
2. **`/compact`** — summarise history into a smaller version. Mid-cost. Use when you need to keep going but history has gotten bloated. Beware: details get lost.
3. **New session entirely** — exit and restart. Forces full reset. Use after long sessions where state has accumulated unpredictably.
4. **Spec-driven multi-session work** — for long-running features, drop spec docs (Module 9) and pick up later. Spec files preserve state where chat can't.

---

## 10.5 — What inflates context the fastest

| Source | Typical bloat |
|---|---|
| Tool results — file reads on large files | 5K-50K tokens per call |
| Conversation history (every turn repeats) | Linear growth |
| Many always-loaded steering files | Constant per-turn cost |
| Verbose system prompts | Constant per-turn cost |
| MCP tool results | Variable; can be large for DB query results |

Defensive habits:

- Prefer `grep` and targeted reads over `cat`ing entire files
- Keep `AGENTS.md` short
- Move bulk content to `fileMatch` steering or `manual` skills
- For long sessions, periodically `/compact` or `/clear`

---

## 10.6 — Patterns that work

- **One session per task.** Don't run "fix the auth bug" and "add a new endpoint" in the same session. Fresh window, fresh focus.
- **Read narrowly.** Before letting the agent `fs_read` a 5K-line file, ask if it can `grep` for the symbol first.
- **Cite, don't re-read.** Tell the agent "you read `auth.py` earlier; assume that still holds" rather than letting it re-read.
- **Push state into files, not chat.** Notes, decisions, intermediate findings — write them to a file the agent can re-read later, instead of accumulating in conversation.
- **Subagents for noisy work.** When investigation will produce a lot of tool calls and reads, spawn a subagent to do it and return a summary (Module 7).

---

## 10.7 — Common failure modes

| Failure | Cause | Fix |
|---|---|---|
| Agent ignores explicit rule | Rule not loaded, or buried under noise | Run `/context`; trim noise; move rule to always-load steering |
| Replies get slower over time | History accumulating | `/compact` or `/clear` |
| Agent contradicts earlier decisions | Context decay; older turns deprioritised | Externalise decisions to a notes file the agent re-reads |
| "Out of context" errors | Window exceeded | Spec-driven workflow; subagent fan-out; aggressive `/clear` |

---

## Mini-exercise

In a real repo, start a fresh kiro-cli session. Run:

```
/context
```

Note the token count. Then have a 5-turn conversation that includes reading 2-3 files. Run `/context` again. Note the growth.

Then `/compact`. Compare. Then `/clear`. Compare again. Get a feel for what each move costs.

---

## Check yourself

| # | Claim | Answer |
|---|---|---|
| 1 | A larger context window solves context management problems. | **False.** Window helps capacity. The signal-budget problem (model attention) gets worse with bloat. |
| 2 | `/compact` is lossless. | **False.** It summarises. Details are dropped. Useful but not free. |
| 3 | Steering files are free because they're loaded automatically. | **False.** They count against the window and cost tokens on every turn. |
| 4 | The right pattern is one long session per project. | **False.** One session per task. Fresh windows for fresh problems. |

---

## What's next

**Module 11 — Orchestration and Planning.** The research → plan → implement loop. How to structure work so the agent's non-determinism doesn't bite, and so long tasks complete without context blowing up.
