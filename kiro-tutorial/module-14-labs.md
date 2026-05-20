# Module 14 — Hands-on Labs

**Part 3 / Patterns and Discipline** &middot; ~90 min total &middot; prereq: Modules 1-13

> Eight progressive labs. Each builds on the previous. Do them in order. By the end you'll have a working `.kiro/` directory exercising every primitive, plus a headless CI integration. Pick a small real repo of yours to work in — not a scratch project. The point is to build something you'll keep using.

---

## Setup

Before starting, confirm:

```bash
kiro-cli --version
# kiro-cli 18.8 or later

cd ~/projects/your-real-repo
git checkout -b kiro-bootstrap
```

You'll be committing `.kiro/` files. Working on a branch keeps it safe.

---

## Lab 1 — Bootstrap `.kiro/`

**Goal:** Create the directory skeleton and the minimum-viable `AGENTS.md`.

**Steps:**

```bash
mkdir -p .kiro/{steering,skills,agents,hooks,specs}

cat > AGENTS.md <<'EOF'
# Agents instructions

## Stack
- Python 3.12, FastAPI, SQLAlchemy
- TypeScript / React (frontend, Vercel)
- Terraform (IaC), AWS (Lambda, SQS, S3, RDS, Bedrock)
- GitLab CI for everything

## Working style
For tasks touching more than 2 files: research → plan → implement.
Stop after research. Stop after plan. Only then implement.

## Don'ts
- Never edit .env* files.
- Never write under infra/prod/.
- Never commit secrets.
EOF

cat > .kiro/README.md <<'EOF'
# .kiro/ — kiro-cli config

- steering/  — durable rules loaded into agent context
- skills/    — invokable workflows (slash commands)
- agents/    — scoped runtime configurations
- hooks/     — bash that runs at lifecycle events
- specs/     — multi-stage gated builds
EOF
```

**Verify:**

```bash
kiro-cli /context
# Should show AGENTS.md as loaded.
```

**What you learned:** The directory layout and the role of `AGENTS.md` as the always-loaded steering file. *(Module 4.)*

---

## Lab 2 — Steering rule with `fileMatch`

**Goal:** Add a conditional steering file that loads only when Terraform files are in context.

**Steps:**

`.kiro/steering/terraform.md`:

```markdown
---
inclusion: fileMatch
fileMatch: "**/*.tf"
---

# Terraform conventions

- Module structure: every module has main.tf, variables.tf, outputs.tf, versions.tf
- Pin provider versions in versions.tf
- Use remote state (S3 + DynamoDB lock). Never local state.
- Tag every resource with: Project, Environment, Owner, ManagedBy=terraform
- For prod, require terraform plan output to be reviewed in MR
```

**Verify:**

```bash
kiro-cli
> Open infra/dev/main.tf
> /context
# Steering "terraform.md" should now appear as loaded.
```

Then in a different session without Terraform files in context, confirm it's NOT loaded.

**What you learned:** The three inclusion modes and how `fileMatch` keeps steering targeted. *(Module 4.)*

---

## Lab 3 — A `security-review` skill

**Goal:** Create a skill that performs a focused security review on a given file or directory.

**Steps:**

`.kiro/skills/security-review/SKILL.md`:

```markdown
---
description: Security-focused review of a file or directory. Looks for secrets in code, unsafe deserialisation, SQL injection risk, IAM over-permissions, and missing input validation. Use when adding or reviewing any auth, payments, or user-input handling code.
---

# Security Review Skill

## Steps
1. Read the target file(s) listed in the user's prompt.
2. Check for:
   - Hardcoded secrets, API keys, tokens (regex: `(api[_-]?key|secret|token|password)`)
   - SQL string concatenation with user input
   - `pickle.loads`, `eval`, `exec` on untrusted data
   - Subprocess calls with `shell=True` and user input
   - IAM policies with `"*"` in Action or Resource
   - Missing input validation on FastAPI endpoint parameters
3. For each finding, output: file:line, severity (high/medium/low), description, suggested fix.
4. End with a summary table of findings by severity.

## Output format
Markdown report with a findings table and per-finding detail.
```

**Verify:**

```bash
kiro-cli
> /security-review src/auth/
# Agent should run the skill workflow.
```

**What you learned:** Skills are slash-invocable workflows; the `description` is critical because it's how the model decides to surface the skill. *(Module 5.)*

---

## Lab 4 — A `code-reviewer` agent

**Goal:** Create a read-only agent specialised for code review.

**Steps:**

`.kiro/agents/code-reviewer.json`:

```json
{
  "name": "code-reviewer",
  "description": "Read-only code review against repo conventions",
  "model": "claude-sonnet-4",
  "prompt": "You are a senior code reviewer. Read the changed files, run linters and tests, produce a markdown review with sections: Summary, Findings (severity-ranked), Suggested changes. Never modify files. Follow the conventions in AGENTS.md.",
  "tools": ["fs_read", "execute_bash"],
  "allowedTools": {
    "execute_bash": ["pytest *", "ruff check *", "mypy *", "git diff *", "git log *"]
  },
  "resources": [
    "file://./AGENTS.md",
    "file://./.kiro/steering/*.md"
  ]
}
```

**Verify:**

```bash
kiro-cli --agent code-reviewer "Review the last commit on this branch"
# Agent should read diff, run linters, produce markdown report.
# Confirm it CANNOT write files — ask it to "save the review to review.md" and confirm refusal.
```

**What you learned:** Agents as scoped runtimes. The tools whitelist is the boundary; the prompt is the persona. *(Module 6.)*

---

## Lab 5 — Subagent fan-out: parallel lint + test

**Goal:** Build an orchestrator that runs linting and tests in parallel via two scoped subagents.

**Steps:**

`.kiro/agents/lint-checker.json`:

```json
{
  "name": "lint-checker",
  "description": "Run ruff and mypy, report errors",
  "model": "claude-haiku-4-5",
  "prompt": "Run ruff and mypy on the project. Report any errors with file:line and the rule violated. Output markdown.",
  "tools": ["execute_bash"],
  "allowedTools": { "execute_bash": ["ruff check *", "mypy *"] }
}
```

`.kiro/agents/test-runner.json`:

```json
{
  "name": "test-runner",
  "description": "Run pytest, report failures",
  "model": "claude-haiku-4-5",
  "prompt": "Run pytest. Report any failures with the test name, file:line, and first 3 lines of the traceback.",
  "tools": ["execute_bash"],
  "allowedTools": { "execute_bash": ["pytest *"] }
}
```

`.kiro/agents/check-orchestrator.json`:

```json
{
  "name": "check-orchestrator",
  "description": "Run linting and tests in parallel, combine results",
  "model": "claude-sonnet-4",
  "prompt": "Spawn lint-checker and test-runner subagents in parallel. Combine their outputs into one report. If either failed, lead with the failures.",
  "tools": ["subagent"],
  "availableAgents": ["lint-checker", "test-runner"],
  "trustedAgents": ["lint-checker", "test-runner"]
}
```

**Verify:**

```bash
kiro-cli --agent check-orchestrator "Run all checks"
# Press Ctrl+G to see subagents spawned in parallel.
# Final output should be a combined report.
```

**What you learned:** Orchestrator pattern — parent has only `subagent`, children are scoped writers/runners. Fan-out reduces wall-clock time. *(Module 7.)*

---

## Lab 6 — `preToolUse` hook to block prod writes

**Goal:** Mechanically block any `fs_write` to paths under `infra/prod/`.

**Steps:**

`.kiro/hooks/pre-tool-use.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

event=$(cat)
tool=$(echo "$event" | jq -r '.tool')
path=$(echo "$event" | jq -r '.input.path // empty')

# Block writes under infra/prod/
if [[ "$tool" == "fs_write" && "$path" == infra/prod/* ]]; then
  echo '{"reason": "Direct writes to infra/prod/ are blocked. Use the prod-deploy spec."}'
  exit 2
fi

# Block .env writes
if [[ "$tool" == "fs_write" && "$path" == *.env* ]]; then
  echo '{"reason": ".env files contain secrets. Edit manually."}'
  exit 2
fi

exit 0
```

```bash
chmod +x .kiro/hooks/pre-tool-use.sh
```

**Verify:**

```bash
kiro-cli
> Create infra/prod/test.tf with an empty resource block
# Should be hard-blocked. The reason should surface to the model.

> Create infra/dev/test.tf with an empty resource block
# Should succeed.
```

**What you learned:** Hooks as the mechanical enforcement layer. Exit code 2 from `preToolUse` is the only way to actually block. *(Module 8.)*

---

## Lab 7 — A spec for a small real feature

**Goal:** Walk a real (small) feature through requirements → design → tasks with human gates.

**Steps:**

Pick a small real feature in your backlog. If you don't have one, use: *"Add a `/health/db` endpoint that returns 200 if the database is reachable, 503 otherwise."*

```bash
kiro-cli
> Create a spec for: "Add a /health/db endpoint that returns 200 if Postgres is reachable, 503 otherwise. Should be unauthenticated and used by the load balancer."
```

Walk all three stages:

1. Agent produces `.kiro/specs/health-db-endpoint/requirements.md` in EARS notation. **Review. Edit. Approve.**
2. Agent produces `design.md` — endpoint location, query used (`SELECT 1`), timeout, error handling. **Review. Push back on anything wrong. Approve.**
3. Agent produces `tasks.md` — atomic tasks. **Review. Approve.**

Then either implement the tasks yourself or let the agent implement them one at a time, running tests after each.

**Verify:**

```bash
ls .kiro/specs/health-db-endpoint/
# requirements.md  design.md  tasks.md
```

Open each file. Confirm the content is something you'd be comfortable showing a teammate as the design record for this feature.

**What you learned:** Specs as gated builds. The cost of catching a bad design decision at the design gate is minutes; at the implementation phase, hours. *(Module 9.)*

---

## Lab 8 — Headless kiro-cli in GitLab CI

**Goal:** Wire the `code-reviewer` agent from Lab 4 into a GitLab CI job that comments on every MR.

**Steps:**

Store `KIRO_API_KEY` as a CI/CD variable (masked, protected) in GitLab project settings.

`.gitlab-ci.yml` (add this job):

```yaml
agent-review:
  stage: test
  image: registry.gitlab.com/your-org/kiro-cli:18.8
  tags: [gitlab--duo]
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  variables:
    KIRO_API_KEY: $KIRO_API_KEY
    AWS_REGION: us-east-1
  script:
    - |
      kiro-cli --no-interactive --agent code-reviewer \
        "Review the diff between $CI_MERGE_REQUEST_DIFF_BASE_SHA and HEAD.
         Focus on the Findings section. Output strict markdown to stdout." \
        > review.md
    - |
      # Post review as MR comment
      curl --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --form "body=<review.md" \
        "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests/$CI_MERGE_REQUEST_IID/notes"
  artifacts:
    paths: [review.md]
    when: always
```

**Verify:**

1. Open a small MR on your branch
2. Watch the `agent-review` job run
3. Confirm `review.md` is uploaded as an artifact
4. Confirm a review comment appears on the MR

**What you learned:** Headless mode + agent config + CI = automated review on every MR. The same `.kiro/code-reviewer.json` runs locally and in CI, with the same conventions. *(Module 12.)*

---

## You're done

You now have a working `.kiro/` directory exercising every primitive:

- **Steering** — `AGENTS.md` + `.kiro/steering/terraform.md`
- **Skills** — `.kiro/skills/security-review/`
- **Agents** — `code-reviewer`, `lint-checker`, `test-runner`, `check-orchestrator`
- **Subagent orchestration** — `check-orchestrator` fans out
- **Hooks** — `.kiro/hooks/pre-tool-use.sh` blocks prod and `.env` writes
- **Specs** — `.kiro/specs/health-db-endpoint/`
- **Headless CI** — `agent-review` job in `.gitlab-ci.yml`

Commit it. Review the MR with a teammate. Then start using it daily. That's how the muscle memory forms.

---

## Course complete

If you started Module 1 not sure what an LLM actually is, and you finish Lab 8 with a working CI integration, you've covered the full arc: **theory → primitives → patterns → working system.**

The mantra one more time, because it's the through-line for everything:

> **Describe with steering. Restrict with agents. Encode know-how in skills.**

Everything else — subagents, hooks, specs, the operating surface, context discipline — supports those three sentences. Refer back to whichever module needs refreshing as you adopt kiro-cli in real work.

Good luck. Ship things.
