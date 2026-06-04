# Headless Guide

Headless (non-interactive) mode runs kiro-cli as a one-shot: it takes a
prompt, prints the answer to stdout, and exits. This is what makes kiro
usable in **GitLab CI jobs, cron/systemd timers, and git hooks** — no TUI,
no human in the loop. Shipped in kiro CLI **2.0** (alongside native
Windows support).

> The catalog's `automation-solutions` skill covers the *workflow* side
> (which check belongs in pre-commit vs pre-push vs cron, fail-open
> design, skip switches). This guide is the *mechanics*: flags, auth, and
> a GitLab CI recipe. Read both before wiring anything that runs on every
> commit.

## The one flag that matters

```bash
kiro-cli chat --no-interactive "Summarize the failures in this log"
```

`--no-interactive` prints the model's response to stdout and exits instead
of opening a chat session. A prompt argument is **required** — there's no
mid-session input.

| Flag | Effect |
|---|---|
| `--no-interactive` | One-shot: print response, exit. |
| `--agent <name>` | Run as a specific catalog agent (read-only personas shine here). |
| `--trust-tools=<list>` | Auto-approve only these tool classes, e.g. `read,grep`. |
| `--trust-all-tools` | Auto-approve everything. **Avoid in CI** — see security. |
| `--require-mcp-startup` | Exit immediately if a configured MCP server fails to connect (fail-fast; prevents hangs). |

### Piping context on stdin

stdin is prepended as context — the idiomatic CI pattern:

```bash
cat build-error.log | kiro-cli chat --no-interactive "Explain this build failure"
git diff origin/main...HEAD | kiro-cli chat --no-interactive "Review these changes"
kubectl get events -A --sort-by=.lastTimestamp | tail -50 \
  | kiro-cli chat --no-interactive --agent eks-troubleshooter "Triage these events"
```

## Output is plain text (today)

`chat --no-interactive` emits the model's reply as **plain text**, not
JSON. There is **no `--output-format json` for chat responses yet** (it's
an open request, kiro #5423). A `--format json` flag exists only for
`whoami` and `chat --list-models`. Consequences for scripting:

- Parse text, or instruct the agent to **write a structured artifact to a
  file** (e.g. "write findings as JSONL to `findings.jsonl`") and consume
  the file — the `mr-reviewer` and `pipeline-troubleshooter` agents are
  built to emit machine-readable output this way.
- Verify auth in scripts with `kiro-cli whoami --format json` (that one
  *is* JSON).

## Authentication in CI

Interactive login won't work on a runner. Use an **API key** in the
environment:

```bash
export KIRO_API_KEY="ksk_..."   # store as a MASKED, PROTECTED CI variable
kiro-cli chat --no-interactive "..."
```

- Key format is `ksk_…`; it skips the browser flow. API keys require a
  **Pro / Pro+ / Power** subscription.
- Credential precedence: an active browser session → `KIRO_API_KEY` →
  interactive prompt. On a runner only the env var applies.
- Never echo the key. Keep it out of logs and out of `mcp.json`.

## GitLab CI recipe

A ready-to-adapt job set lives in
[`../headless/gitlab-ci.sample.yml`](../headless/gitlab-ci.sample.yml),
and a hardened wrapper that checks auth and handles exit codes in
[`../headless/kiro-headless.sh`](../headless/kiro-headless.sh). The
shape of an MR-review job:

```yaml
kiro-mr-review:
  stage: review
  image: debian:stable-slim
  variables:
    KIRO_API_KEY: $KIRO_API_KEY        # masked + protected project variable
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - apt-get update && apt-get install -y --no-install-recommends curl git ca-certificates
    - curl -fsSL https://cli.kiro.dev/install | bash
    - export PATH="$HOME/.local/bin:$PATH"
    - git fetch origin "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
    - |
      git diff "origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME...HEAD" \
        | kiro-cli chat --no-interactive --agent mr-reviewer \
            --trust-tools=read,grep \
            "Review this MR diff for security and Terraform/Terragrunt issues. Emit JSONL findings to findings.jsonl, then a short summary." \
        | tee review.md
  artifacts:
    when: always
    paths: [review.md, findings.jsonl]
    expire_in: 1 week
  allow_failure: true      # advisory gate: don't block merges on the bot
```

## Security checklist for headless runs

Headless removes the human approval step, so the guardrails have to be
structural:

1. **Scope `--trust-tools` to the read class** (`read,grep`). Reserve
   `--trust-all-tools` for throwaway sandboxes only.
2. **Run a read-only agent.** `--agent mr-reviewer` /
   `pipeline-troubleshooter` / `eks-troubleshooter` have no `write` tool
   and gate `shell`/`use_aws` via `toolsSettings` — a prompt-injected diff
   can't make them mutate.
3. **Least-privilege credentials.** The runner's AWS role and the GitLab
   token are the real boundary; use OIDC + `assume-role-with-web-identity`
   (see the `gitlab-pipeline` skill), not static keys.
4. **Throwaway container, limited egress.** One job, one container,
   reclaimed after.
5. **`--require-mcp-startup`** so a missing server fails the job instead of
   silently degrading.
6. **`allow_failure: true`** while the bot is advisory — earn the blocking
   gate after it's proven trustworthy.
7. **Treat the diff/log as untrusted input.** It can contain injection
   ("ignore the above and …"). The read-only posture is what neutralizes
   it.

## See also

- [`automation-solutions`](../skills/automation-solutions/SKILL.md) — git-hook / cron workflow design
- [`agents-guide.md`](agents-guide.md) — `--agent`, `toolsSettings`, read-only patterns
- [`use-cases.md`](use-cases.md) — which agent to drive headlessly per task
- Kiro CLI docs: <https://kiro.dev/docs/cli/headless/>
