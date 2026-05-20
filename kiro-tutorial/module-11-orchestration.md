# Module 11 — Orchestration and Planning

**Part 3 / Patterns and Discipline** &middot; ~10 min read &middot; prereq: Module 10

> The non-deterministic engine works best on small, well-scoped pieces. The skill is structuring real work so it decomposes into pieces the agent can ship reliably. That's orchestration.

---

## 11.1 — The research → plan → implement loop

For anything beyond a one-line change, run this three-pass pattern in kiro-cli:

1. **Research** — agent reads the relevant files, runs `grep`, queries MCP servers. Goal: ground the model in the actual state of the code. Output: a written summary of what exists today.
2. **Plan** — agent proposes an approach. Files to change, order of changes, risks. Output: a numbered plan. **You review.**
3. **Implement** — agent executes the plan, one step at a time, running tests after each.

The gate between 2 and 3 is where you catch most disasters. The cost of a bad plan corrected in 2 is one minute. The cost of a bad plan implemented in 3 is hours.

---

## 11.2 — Why not "just do it"

It's tempting to say "fix this bug" and let the agent loose. Why structure?

| Without research → plan → implement | With it |
|---|---|
| Agent invents details that don't match reality | Grounded in real code |
| You discover bad approach after files are changed | Catch in plan phase |
| Long opaque tool-call stream | Reviewable artefact at each stage |
| Hard to resume after interruption | Plan is a re-entry point |
| Token waste on speculative reading | Targeted reads |

---

## 11.3 — How to invoke the pattern in practice

You don't need a primitive for this — a steering rule and a prompt convention is enough.

`AGENTS.md` snippet:

```markdown
## Working style
For any task touching more than 2 files:
1. First, summarise what you've read and what currently exists. Stop and confirm.
2. Then propose a numbered plan. Stop and confirm.
3. Only then implement, one step at a time, running tests after each.
Do not skip steps. Do not combine them.
```

For larger work, use a **spec** (Module 9). For one-off-but-careful work, this lighter pattern works.

---

## 11.4 — TODO lists and progress reporting

For multi-step implementations, ask the agent to maintain an explicit TODO list:

```
Implement the API key rotation feature. Maintain a TODO list in this conversation,
mark items as you complete them, and call report_progress between items.
```

Two benefits:

- **Recoverable.** If context decays or session restarts, the TODO is the resume point.
- **Visible.** You can see at a glance what's done and what isn't.

The `report_progress` built-in tool surfaces status to the TUI — useful for long-running tasks.

---

## 11.5 — Subagent fan-out for parallel orchestration

When research or implementation has independent branches, use subagents (Module 7):

- **Research fan-out** — parent dispatches subagents to investigate different subsystems in parallel; collects summaries.
- **Implementation fan-out** — after plan approval, parent dispatches each task to a scoped writer subagent.

Caveat: only use fan-out when work is genuinely independent. Sequential tasks with state dependencies are simpler in one agent.

---

## 11.6 — When orchestration becomes overhead

Don't apply this pattern when:

- The task is trivial (one-liner, obvious change)
- You're exploring or prototyping (research-as-you-go is fine)
- The agent will produce a discardable artefact (a one-shot draft)

Match the discipline to the stakes.

---

## 11.7 — Patterns

| Pattern | When | Tools |
|---|---|---|
| Inline 3-pass (chat) | Multi-file change, one session | Steering rule + prompt convention |
| Spec | Feature, requirements unclear, multi-session | Module 9 |
| Orchestrator + subagents | Parallel investigation or scoped writes | Module 7 |
| TODO list in chat | Long implementation, one session | `report_progress` + prompt |

---

## Mini-exercise

Pick a real medium-complexity task in your repo. Run it in kiro-cli two ways:

**Way 1:** "Just do it." Single prompt with the task and no structure. Note what happens.

**Way 2:** Same task, but include in the prompt:
```
Three phases: (1) research and summarise. Stop. (2) Propose a numbered plan. Stop. (3) Implement, one step at a time.
```

Compare quality, time-to-correct, and how confident you were in the outcome. The structure usually wins by a wide margin for anything non-trivial.

---

## Check yourself

| # | Claim | Answer |
|---|---|---|
| 1 | The research phase is wasted time. | **False.** It's the cheapest place to catch wrong assumptions. |
| 2 | Specs and the 3-pass pattern are the same thing. | **False.** Specs are persisted, multi-session, with formal documents. 3-pass is in-conversation and lightweight. |
| 3 | Fan-out always speeds things up. | **False.** Only when tasks are genuinely independent. Sequential work parallelised becomes coordination overhead. |
| 4 | `report_progress` is required for orchestration. | **False.** It helps visibility but isn't load-bearing. A maintained TODO in chat works too. |

---

## What's next

**Module 12 — Operating Surface.** All the slash commands, headless mode, auth, tier gotchas, and editor integration. The interface beneath what you've been using.
