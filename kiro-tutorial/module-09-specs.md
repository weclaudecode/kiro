# Module 9 — Specs

**Part 2 / kiro-cli Primitives** &middot; ~12 min read &middot; prereq: Module 8

> Specs are the last primitive. For non-trivial work — anything beyond "tweak this function" — you want explicit alignment *before* code. Specs give you a three-stage, human-gated build: requirements &rarr; design &rarr; tasks. The output is a directory of markdown files the agent then implements.

---

## 9.1 — When to use a spec

Use a spec when:

- The task touches more than 2-3 files
- Requirements are unclear and need to be teased out
- You want a record of what was decided before code existed
- The work spans multiple sessions (you need persistent state)
- Stakeholders need to review the plan before execution

Skip the spec when:

- The task is a clear one-shot ("rename this variable everywhere")
- You already know the design
- The work fits in one conversation

> Specs trade speed for clarity. For agentic work, the clarity is usually worth it.

---

## 9.2 — The three documents

A spec is a directory:

```
.kiro/specs/<feature-name>/
├── requirements.md   # What we're building, in EARS notation
├── design.md         # How we'll build it
└── tasks.md          # The implementation breakdown
```

Each document is built in order, with a **human-in-the-loop gate** before moving to the next.

| Stage | What it contains | Gate |
|---|---|---|
| Requirements | EARS-format requirements, acceptance criteria | User reviews + approves before design |
| Design | Architecture, data model, interfaces, sequence | User reviews + approves before tasks |
| Tasks | Numbered, parallelisable, atomic tasks | User can edit before execution |

---

## 9.3 — EARS notation

**Easy Approach to Requirements Syntax.** Five canonical patterns that force unambiguous requirements:

| Pattern | Form | Example |
|---|---|---|
| Ubiquitous | "The system shall X" | The system shall log every authentication attempt. |
| Event-driven | "When X, the system shall Y" | When a user submits an invalid token, the system shall return HTTP 401. |
| State-driven | "While X, the system shall Y" | While in maintenance mode, the system shall return HTTP 503. |
| Conditional | "If X, then the system shall Y" | If the rate-limit is exceeded, then the system shall return HTTP 429. |
| Optional | "Where X, the system shall Y" | Where multi-tenant is enabled, the system shall scope all queries by tenant_id. |

EARS feels stilted at first. That's the point — **ambiguity in requirements becomes bugs in code.** Forcing the structure exposes the ambiguity before code.

---

## 9.4 — A worked example: requirements.md

```markdown
# Requirements: API Key Rotation

## REQ-1: Key generation
The system shall generate new API keys using 256-bit random tokens.

## REQ-2: Active key rotation
When an admin triggers rotation for a tenant, the system shall:
- Generate a new key marked `active`
- Mark the previous key `deprecated` with a 30-day expiry
- Emit a `key.rotated` event to the audit log

## REQ-3: Deprecated key acceptance
While a key is in `deprecated` state and within its expiry window, the system
shall accept it but return a `X-Key-Deprecated` response header.

## REQ-4: Expiry enforcement
If a key has expired, the system shall return HTTP 401 with body
`{"error": "key_expired"}`.

## Out of scope
- Per-endpoint key restrictions (future work)
- Programmatic rotation by tenant (admin only for v1)
```

A senior engineer can sanity-check this in two minutes. The agent has zero room to invent behavior.

---

## 9.5 — design.md

After requirements approval, the agent produces a design:

```markdown
# Design: API Key Rotation

## Data model
- `api_keys` table:
  - `id` (uuid), `tenant_id` (uuid), `hash` (sha256), `status` (enum: active|deprecated|revoked),
    `expires_at` (timestamp nullable), `created_at`, `rotated_from_id` (nullable)

## API surface
- `POST /admin/tenants/{tenant_id}/keys/rotate` — admin endpoint
- Existing middleware: `verify_key()` updated to handle `deprecated` status

## Sequence (rotation)
1. Admin POST hits the rotate endpoint
2. Service generates new token, hashes, inserts as `active`
3. Existing `active` row updated to `deprecated`, `expires_at = now + 30d`
4. `key.rotated` event published to SNS
5. Response returns the new plaintext token (one-time)

## Tradeoffs considered
- Soft delete vs hard delete: soft delete chosen for audit trail
- 30-day expiry chosen to match SOC2 requirements
```

User reviews. If the data-model or API choice is wrong, this is the cheapest moment to catch it — before any code.

---

## 9.6 — tasks.md

Final stage — atomic tasks the agent (or you) will execute:

```markdown
# Tasks: API Key Rotation

- [ ] T1: Create migration for `api_keys` schema changes (add status, expires_at, rotated_from_id)
- [ ] T2: Update `ApiKey` Pydantic model with new fields
- [ ] T3: Update `verify_key()` middleware to handle `deprecated` status + response header
- [ ] T4: Add `POST /admin/tenants/{tenant_id}/keys/rotate` endpoint
- [ ] T5: Publish `key.rotated` event to SNS topic `audit-events`
- [ ] T6: Tests: rotation flow, deprecated key acceptance, expiry enforcement
- [ ] T7: Update docs: `docs/api/auth.md`

Dependencies: T2 depends on T1. T3-T5 can run in parallel after T2.
```

The agent (or a fan-out orchestrator) implements one task at a time, marking it done, running tests. The tasks list is your durable progress tracker.

---

## 9.7 — Specs vs other primitives

| You want… | Use |
|---|---|
| Quick rules the agent applies always | Steering |
| A named, repeatable workflow | Skill |
| A constrained runtime | Agent config |
| Hard enforcement | Hook |
| **Multi-stage, gated build of something non-trivial** | **Spec** |

Specs are the heaviest primitive. Don't reach for them on small tasks — overhead > value.

---

## 9.8 — Patterns

- **Spec for feature, skill for procedure.** A spec builds a feature once; a skill runs a procedure repeatedly.
- **Specs as RFC.** Treat `requirements.md` and `design.md` like internal RFCs — review them as artefacts, not just intermediate agent output.
- **Tasks become MR titles.** Each task is small enough to be one MR. Helps with review.
- **Pause between stages.** Don't let the agent rush all three stages in one turn. The gate is the point.

---

## Mini-exercise

Pick a small real feature your team has in flight (or an idea). In kiro-cli, ask:

```
Create a spec for: "Add a per-tenant audit log that captures all API key operations."
```

Walk through all three stages. Stop at each gate, edit the documents, push back on assumptions the agent made. Notice how much clearer the implementation phase becomes when the design is settled.

---

## Check yourself

| # | Claim | Answer |
|---|---|---|
| 1 | Specs are for any task more than 50 lines of code. | **False.** Heuristic is multi-file + unclear requirements. Many large refactors don't need a spec; some small features do. |
| 2 | EARS notation is just a style preference. | **False.** It forces unambiguous requirements. Ambiguity in requirements becomes bugs. |
| 3 | I can skip the design stage and go straight from requirements to tasks. | **Technically yes, practically no.** The design stage is where most expensive mistakes get caught. |
| 4 | The agent should auto-approve and continue between stages. | **False.** The human gate is the entire point of specs. |

---

## End of Part 2

You now have all six kiro-cli primitives:

- **Steering** — durable rules in markdown
- **Skills** — invokable workflows as slash commands
- **Agents** — scoped runtime configurations
- **Multi-agent / Subagents** — orchestration with bounded children
- **Hooks** — mechanical enforcement at lifecycle events
- **Specs** — multi-stage gated builds with human review

Part 3 is about **using these well** — context management, planning, the operating surface, best practices, and hands-on labs.

**Module 10 — Context Management.** The most important skill in agentic coding.
