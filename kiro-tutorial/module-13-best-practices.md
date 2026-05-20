# Module 13 — Best Practices and Failure Modes

**Part 3 / Patterns and Discipline** &middot; ~11 min read &middot; prereq: Modules 1-12

> A synthesis. The patterns that distinguish teams who get value from kiro-cli from teams who fight it. Plus the LICENSE gotcha that's caught more than one team off-guard.

---

## 13.1 — The mantra

> **Describe with steering. Restrict with agents. Encode know-how in skills.**

Three sentences. Internalise them. Every kiro-cli design decision should be testable against this.

- A team rule? → steering
- A repeatable procedure? → skill
- A bounded runtime for a risky job? → agent

When in doubt, default to the lightest primitive that fits.

---

## 13.2 — Treat `.kiro/` as code

`.kiro/` files are *infrastructure*. Treat them accordingly:

- **Commit them.** Steering, skills, agents, hooks, specs — all in the repo, reviewed in MRs.
- **Lint them.** Validate JSON configs, check YAML front-matter, ensure hook scripts are executable.
- **Test them.** When you change a hook, run kiro-cli with a known prompt and assert behavior.
- **Version them.** Pin kiro-cli versions in CI; upgrade deliberately; note breaking changes.
- **Document them.** A short `README.md` in `.kiro/` explaining what each piece does.

The team that doesn't do this ends up with mystery configs no one can explain six months later.

---

## 13.3 — Failure modes in the wild

| Failure | Root cause | Antidote |
|---|---|---|
| Agent does the wrong thing and you didn't catch it | Output not reviewed; auto-merge | Treat output as untrusted; review like any human MR |
| `.kiro/` drift across team | No source of truth; private global configs | Workspace configs win; deprecate global where possible |
| One giant agent does everything | Reaching for the default agent for everything | Build scoped agents; switch via <code>/agent</code> |
| Steering bloat slows every turn | Every team rule added to <code>always</code> | Move to <code>fileMatch</code> or <code>manual</code> aggressively |
| Subagents do unexpected writes | Hook on parent doesn't fire on children | Lock down child configs; combine layers |
| Spec stages collapsed into one turn | Convenience over discipline | Enforce gates; review at each stage |
| Hallucinated APIs / config keys | No grounding; agent didn't read source | Steering rule: "verify by reading actual source before answering" |
| Cost explosions | Long sessions; no <code>/clear</code> habit | Session per task; periodic compact/clear |

---

## 13.4 — When NOT to use kiro-cli

Honest list:

- **Deterministic refactors.** A rename, a regex substitution, a codemod. Use a real refactor tool.
- **Code that must be exactly reproducible.** Generated migrations, build artefacts. The non-determinism bites.
- **Hot-path performance work.** The agent loop adds latency. Profile manually, edit manually.
- **Greenfield architectural decisions.** The agent has no taste. Decide first, implement second.
- **Anywhere a wrong answer is catastrophic and undetectable.** Money calculations without tests, security-critical crypto, etc.

Knowing where the tool doesn't fit makes you better at recognising where it does.

---

## 13.5 — LICENSE gotcha

> **kiro-cli's LICENSE forbids use in conjunction with OpenClaw, NemoClaw, and similar reverse-engineered or Anthropic-API-fronting clients.**

This matters if your team uses (or experiments with) those tools. Concretely:

- Do not mix kiro-cli configs/skills with OpenClaw/NemoClaw setups
- Do not pipe kiro-cli output into one of those clients, or vice versa
- If a project uses both, separate the workflows entirely

Audit your team's stack. If anyone is doing this, fix it before it becomes a procurement issue.

---

## 13.6 — Habits of effective teams

Observed in teams that ship reliably with kiro-cli:

- **One scoped agent per risky workflow.** Never use default for prod-adjacent work.
- **AGENTS.md under 100 lines.** Anything more, move to <code>fileMatch</code>.
- **A `code-reviewer` agent that runs in CI on every MR.** Cheap, useful, agent-output is reviewed by humans regardless.
- **Periodic <code>.kiro/</code> review.** A 30-minute monthly grooming session pays back tenfold.
- **Specs for anything beyond a 2-file change.** Cheap discipline; massive savings.
- **Templates for new agents and skills.** Lowers the activation energy to do things properly.

---

## 13.7 — Habits of struggling teams

| Anti-pattern | Why it hurts |
|---|---|
| One person owns all `.kiro/` configs | Bus factor of one |
| Default agent for everything | No least-privilege; surprises happen |
| Skills with no description | Agent never proposes them; users forget they exist |
| Hooks that always exit 0 | Silent failure mode |
| Specs treated as paperwork | Stages get rushed, defeating the point |
| No CI lint on `.kiro/` JSON | Broken configs reach prod-adjacent workflows |
| Treating agent output as authoritative | Skipped reviews; bugs ship |

---

## 13.8 — A 30-day adoption arc for a team

If you're rolling kiro-cli into a team, this sequence works:

| Week | Goal |
|---|---|
| 1 | Everyone installed; `AGENTS.md` written; one shared steering file |
| 2 | First skill (low-stakes — repo-audit or doc-update); team uses it |
| 3 | First custom agent (code-reviewer); wired into CI on MRs |
| 4 | First hook (block prod writes); first spec (next real feature) |

After 30 days you have the full stack in production use. Add subagents and orchestrators when the natural fan-out cases appear.

---

## Check yourself

| # | Claim | Answer |
|---|---|---|
| 1 | `.kiro/` configs should live in everyone's home directory for personalisation. | **False.** Workspace configs win for team consistency; global is for personal. |
| 2 | The default agent is fine for production workflows if you trust the LLM. | **False.** Trust is not a security model. Build scoped agents. |
| 3 | I can use kiro-cli alongside OpenClaw. | **False.** LICENSE forbids it. |
| 4 | Specs are only useful if every MR uses one. | **False.** Use them when the size/risk justifies the overhead. Most MRs won't need one. |

---

## What's next

**Module 14 — Hands-on Labs.** Eight progressive exercises that take a fresh repo through full kiro-cli adoption: bootstrap, steering, skill, agent, subagent, hook, spec, headless CI. Do them in order.
