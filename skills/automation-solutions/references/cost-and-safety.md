# Cost and safety for headless kiro

Headless automation runs kiro with no human in the loop, so the guardrails
matter more than in interactive use.

## Never let a hook write code

Every workflow uses `--trust-tools read,grep`. The agents are defined read-only
(`tools` and `allowedTools` limited to `read`/`@git`). Combined, that means a
hook can review, propose, and report — but never edit a file or run a shell
command on its own. Proposals (doc patches, steering diffs) are emitted as
unified diffs for a human to apply with `git apply --check`.

If you add a workflow that needs to write (e.g. auto-formatting), keep it in a
separate hook with an explicit, narrow `allowedPaths` — don't loosen the review
hooks.

## Fail open, skip easily

- **Fail open:** `_lib.sh`'s `kiro_ready` exits the hook cleanly (0) when
  `kiro-cli` is missing or `KIRO_API_KEY` is unset. A missing binary or key must
  never block a commit or push.
- **Skip switch:** every hook honors `KIRO_SKIP=1 git commit ...`. This beats
  `--no-verify`, which disables *all* hooks at once — `KIRO_SKIP` targets only
  the kiro ones and leaves other hooks (linters, etc.) running.

## Cost

Headless mode burns credits per call.

- Pre-commit on every save/commit is the most expensive pattern. Pre-push is the
  sweet spot — same coverage, far fewer invocations.
- The `commit-msg` validator is a pure-local regex check: zero API cost.
- Cron jobs are bounded (N failed pipelines, one scan, one weekly summary), so
  their cost is predictable. Cap pipeline triage with `--per-page` and the
  lookback window.

## API key scope

- Treat `KIRO_API_KEY` like an AWS access key: `.envrc` + `direnv` per project,
  or `~/.config/claude/secrets.env` (`chmod 600`) for cross-project use. Never
  commit it. See the `secrets-handling` steering.
- SSO orgs need an admin to enable API keys; for personal use, generate one from
  Kiro account settings.
- In cron, read the key from a `chmod 600` env file (systemd `EnvironmentFile`,
  or `source` at the top of the script) — not from a committed crontab.

## License / harness isolation

Kiro's ToS prohibit pairing it with OpenClaw / NemoClaw-style harnesses. If your
automation stack mixes those, keep kiro invocations isolated — their own shell,
their own env — from those harnesses. Don't co-invoke them in the same wrapper.

## Hook portability

`.git/hooks/` is never tracked by git, so hooks placed there don't follow the
repo. Use `core.hooksPath` pointing at a tracked `.githooks/` directory (what
`install-hooks.sh` sets up), or a framework like `lefthook` / `pre-commit`, so
the team and future-you on a new machine get the hooks automatically.
