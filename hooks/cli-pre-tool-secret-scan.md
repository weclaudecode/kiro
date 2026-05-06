<!-- Install: this is NOT a standalone file. Paste the JSON below into the
     `hooks` block of one of your agent JSONs (~/.kiro/agents/*.json or
     <project>/.kiro/agents/*.json). CLI hooks live inside agent config,
     not in a hooks/ directory. -->

# CLI hook: pre-tool secret scan

Blocks shell commands that look like they expose secrets — `echo`/`printf`
of common AWS or token environment variables, or `cat` of well-known
secret files.

## What it does

Runs before every `shell` tool call. The script reads the proposed command
from stdin (kiro passes hook input as JSON), greps it for risky patterns,
and exits non-zero (with a message on stderr) to block the call.

## Snippet to paste into an agent

Add this `hooks` block to any agent JSON that has `shell` in its `tools`:

```json
"hooks": {
  "preToolUse": [
    {
      "matcher": "shell",
      "command": "$HOME/.kiro/hooks/scripts/secret-scan.sh",
      "timeout_ms": 5000
    }
  ]
}
```

## Companion script

Place this at `~/.kiro/hooks/scripts/secret-scan.sh` (chmod +x):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Kiro passes a JSON payload on stdin: {"tool":"shell","input":{"command":"..."}, ...}
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.input.command // .input.cmd // empty')"

# Patterns that should never appear in a shell call we let through
patterns=(
  'echo[[:space:]]+\$AWS_'
  'printf[[:space:]].*\$AWS_'
  'echo[[:space:]]+\$.*(SECRET|TOKEN|PASSWORD|API_KEY)'
  'cat[[:space:]]+.*\.envrc'
  'cat[[:space:]]+.*secrets\.env'
  'cat[[:space:]]+.*\.aws/credentials'
)

for p in "${patterns[@]}"; do
  if printf '%s' "$cmd" | grep -E -q "$p"; then
    printf '[secret-scan] blocked: command matches pattern /%s/\n' "$p" >&2
    exit 2
  fi
done

exit 0
```

Requires `jq`. Adjust patterns to your environment. A non-zero exit code
from a kiro CLI hook blocks the tool call and surfaces stderr to the
agent.
