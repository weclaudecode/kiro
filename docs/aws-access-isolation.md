# Locking down kiro-cli's AWS access on a shared devbox

## TL;DR

Hooks alone cannot enforce read-only. Use **layered defense**:

| Layer | What it does | Bypassable? |
|---|---|---|
| **1. IAM read-only role** | AWS denies write APIs at the source | No — this is the only real enforcement |
| **2. `HOME` isolation (bwrap)** | Kiro can't reach your admin AWS profile | No, if launched correctly |
| **3. `preToolUse` hook** | Fast feedback on `use_aws` / `aws` shell commands | Yes (boto3 in a Python script) |
| **4. Agent design** | No `shell`/`use_aws` tools for review-only agents | Yes if user runs a permissive agent |
| **5. CloudTrail alerting** | After-the-fact detection of attempted misuse | N/A — detective control |

The hook is useful but **not enforcement**. The two `Yes`-bypassable layers don't stand alone — they protect against accidents and give a UX signal, while layers 1 + 2 stop a determined model.

---

## 1. Threat model

- **Asset:** ability to mutate or destroy resources in your AWS accounts.
- **Adversary:** the LLM, either through (a) genuine error, (b) a misleading prompt, or (c) prompt injection from a file/tool result the model reads. The model is not malicious, but it has the same shell access you do.
- **Attack surface:** anything kiro-cli can do that ends up calling AWS — `aws` CLI invocations, `use_aws` built-in tool, the AWS API MCP server, any Python/Go/Node script that imports an AWS SDK.
- **Out of scope:** root-level escapes, kernel exploits, tampering with kiro itself. If your devbox can't trust its own kernel, none of this helps.

---

## 2. Why hooks alone fail

`preToolUse` hooks (matcher: `*`) fire before kiro invokes a tool. They can block by exiting `2`. Sounds enough — until you trace what the model can do:

- **Match `use_aws` →** model writes `python3 -c "import boto3; boto3.client('s3').delete_object(...)"` and runs it via `execute_bash`. Hook now needs to also match `execute_bash` and pattern-match Python source.
- **Match `execute_bash` for `aws ` and `python` →** model writes a script via `fs_write` and runs it as `./script.sh`. Hook needs to also match `fs_write` and statically analyze the file content. This is regex-vs-Turing-machine; you lose.
- **Match `fs_write` for boto3 patterns →** model uses `import botocore` directly, or `urllib.request` against the AWS REST API with SigV4, or a Go binary. You can't enumerate every SDK.
- **`AWS_PROFILE` env-var trick →** `boto3.Session(profile_name='admin')` overrides `AWS_PROFILE` in the env. Confirmed in [boto3#2403](https://github.com/boto/boto3/issues/2403) and [boto3 credentials guide](https://docs.aws.amazon.com/boto3/latest/guide/credentials.html). Explicit profile in code beats environment.

**Conclusion:** the hook is a tripwire and a UX nudge — fast feedback when the model does the obvious thing. It is not enforcement. Enforcement has to live where the model can't reach: the IAM control plane and the filesystem boundary.

---

## 3. Layer 1 — IAM-enforced read-only role (mandatory)

Create a dedicated IAM Identity Center permission set. This is the only layer that AWS itself enforces, so even a bypass-everything model can't write.

### Permission set: `KiroReadOnly`

**Attached AWS managed policy:**
- `ReadOnlyAccess` (covers most read APIs across services)

**Inline deny (block secret reads — read-only is not the same as safe-to-leak):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenySecretReads",
      "Effect": "Deny",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:BatchGetSecretValue",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyCredentialEnumeration",
      "Effect": "Deny",
      "Action": [
        "iam:GetAccessKeyLastUsed",
        "iam:ListAccessKeys",
        "iam:GetLoginProfile",
        "iam:GetSSHPublicKey",
        "sts:GetSessionToken",
        "sts:AssumeRole"
      ],
      "Resource": "*"
    }
  ]
}
```

The second statement matters: a "read-only" model that can `sts:AssumeRole` into a more-privileged role escapes the box. Block role-chaining outright.

**Session duration:** 4 hours max (forces a re-login if the model has been running for a while).

### Assignment

Assign `KiroReadOnly` to your user in IAM Identity Center for **every account where you might run kiro**. Same accounts as your admin assignment, different permission set.

---

## 4. Layer 2 — `HOME` isolation via `bwrap` (mandatory)

The model cannot reach what it cannot see. Give kiro a different `HOME` whose `~/.aws/` contains only the read-only profile.

### Set up the alternate HOME

```bash
mkdir -p ~/kiro-home/.aws
cat > ~/kiro-home/.aws/config <<'EOF'
[sso-session kiro]
sso_start_url   = https://your-org.awsapps.com/start
sso_region      = eu-west-1
sso_registration_scopes = sso:account:access

[profile kiro-readonly]
sso_session     = kiro
sso_account_id  = 111122223333
sso_role_name   = KiroReadOnly
region          = eu-west-1
output          = json
EOF
chmod -R go-rwx ~/kiro-home
```

Repeat the `[profile kiro-readonly-<accountname>]` block per AWS account.

### Install bubblewrap

```bash
sudo apt install bubblewrap        # Ubuntu/Debian
sudo dnf install bubblewrap        # Fedora/RHEL
```

`bwrap` is rootless (uses user namespaces). On most modern distros no extra setup needed — verify with `bwrap --bind / / true`.

### Wrapper script: `~/bin/kiro-ro`

```bash
#!/usr/bin/env bash
# Launches kiro-cli inside a sandbox where HOME contains only the
# read-only AWS profile. Network is shared (kiro needs to talk to AWS
# and to its own backend). The host filesystem is read-only except for
# the project directory and kiro-home.
set -euo pipefail

KIRO_HOME="${KIRO_HOME:-$HOME/kiro-home}"
PROJECT_DIR="${1:-$PWD}"

[[ -d "$KIRO_HOME" ]]    || { echo "kiro-home not found: $KIRO_HOME" >&2; exit 1; }
[[ -d "$PROJECT_DIR" ]]  || { echo "project dir not found: $PROJECT_DIR" >&2; exit 1; }

exec bwrap \
  --ro-bind /usr /usr \
  --ro-bind /etc /etc \
  --ro-bind /var /var \
  --ro-bind /opt /opt \
  --symlink usr/bin /bin \
  --symlink usr/sbin /sbin \
  --symlink usr/lib /lib \
  --symlink usr/lib64 /lib64 \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --bind "$KIRO_HOME" "$HOME" \
  --bind "$PROJECT_DIR" "$PROJECT_DIR" \
  --chdir "$PROJECT_DIR" \
  --setenv HOME "$HOME" \
  --setenv AWS_PROFILE kiro-readonly \
  --setenv AWS_SDK_LOAD_CONFIG 1 \
  --unsetenv AWS_ACCESS_KEY_ID \
  --unsetenv AWS_SECRET_ACCESS_KEY \
  --unsetenv AWS_SESSION_TOKEN \
  --share-net \
  --die-with-parent \
  --new-session \
  -- kiro-cli "$@"
```

```bash
chmod +x ~/bin/kiro-ro
```

### Daily usage

```bash
# In a shell with your normal admin profile loaded — once per session:
aws sso login --profile kiro-readonly       # populates ~/kiro-home/.aws/sso/cache/

# Then run kiro inside the sandbox:
cd ~/code/some-project
kiro-ro

# Want to switch AWS accounts? Different profile, same pattern:
KIRO_HOME=~/kiro-home AWS_PROFILE=kiro-readonly-prod kiro-ro
```

### Why this works

- The sandboxed process sees `$HOME` pointing at `~/kiro-home`, which contains **only** the `KiroReadOnly` profile config and its SSO cache.
- Your admin `~/.aws/credentials` and `~/.aws/config` are not bind-mounted into the sandbox — they don't exist from the model's perspective.
- The `--unsetenv` lines wipe any stray static credentials inherited from the parent shell.
- `boto3.Session(profile_name='admin')` returns `ProfileNotFound` because `admin` doesn't exist in the sandboxed `~/.aws/config`.
- `--share-net` keeps network so kiro can call AWS; AWS rejects writes via IAM (Layer 1).
- `--die-with-parent` ensures the sandbox can't outlive your shell.

### What this does NOT protect against

- Your project directory is still bind-mounted writable. The model can edit any file in there. That's intentional — you're using kiro to write code.
- The sandbox shares your network. The model can `curl` external URLs. Combine with an egress proxy if your devbox already has one.
- Anything kiro writes inside the sandbox to `~/.aws/config` persists because `~/kiro-home` is bind-mounted (not copy-on-write). Watch for the model trying to add a profile.

---

## 5. Layer 3 — `preToolUse` hook (recommended tripwire)

Even with layers 1 + 2, a hook gives the model fast, in-context feedback ("this is denied, don't try again") and surfaces attempts in your terminal. Without it, the model just sees an opaque `AccessDenied` from AWS 30s into a call.

### Hook script: `~/kiro-home/.kiro/hooks/scripts/aws-readonly-guard.sh`

```bash
#!/usr/bin/env bash
# preToolUse hook: block obvious AWS mutation attempts at the kiro layer.
# Reads kiro's hook payload on stdin. Exits 2 to BLOCK (and surface stderr
# to the LLM). Other non-zero exits only warn — use 2 to enforce.
#
# Coverage: use_aws, execute_bash (`aws ...` and `python ... boto3 ...`),
# fs_write (writing files containing AWS SDK calls).
set -euo pipefail

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

# AWS subcommands that are READ-only — anything else is denied for `aws` CLI.
# This is a denylist-by-default approach: if it's not on the allow list, block.
allowed_aws_verbs='^(get-|describe-|list-|head-|search-|select-|lookup-|export-|view-|test-|validate-|simulate-|preview-|estimate-|check-|count-|scan-|query-|batch-get-|sso |configure |sts get-caller-identity)'

deny() {
  printf '[aws-readonly-guard] BLOCKED: %s\n' "$1" >&2
  exit 2
}

case "$tool_name" in
  use_aws|aws)
    # use_aws tool: tool_input has structured AWS call info
    op="$(printf '%s' "$input" | jq -r '.tool_input.operation // .tool_input.action // .tool_input.command // empty')"
    [[ -z "$op" ]] && exit 0
    if ! [[ "$op" =~ $allowed_aws_verbs ]]; then
      deny "use_aws operation '$op' is not on the read-only allow list."
    fi
    ;;

  execute_bash|shell)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    # Block any aws CLI call whose first sub-token isn't a read verb.
    while IFS= read -r aws_invocation; do
      verb="$(printf '%s' "$aws_invocation" | awk '{ for (i=2;i<=NF;i++) if ($i !~ /^-/) { print $i; exit } }')"
      if [[ -n "$verb" ]] && ! [[ "$verb $(echo "$aws_invocation" | awk '{print $3}')" =~ $allowed_aws_verbs ]]; then
        deny "shell aws call uses non-read verb: $verb"
      fi
    done < <(printf '%s\n' "$cmd" | grep -oE '(^|[;&|]| )aws [^;&|]+' || true)

    # Block obvious boto3 / botocore one-liners with mutating intent.
    if printf '%s' "$cmd" | grep -E -q 'boto3.*\.(create_|delete_|put_|update_|modify_|attach_|detach_|start_|stop_|terminate_|run_|reboot_|associate_|disassociate_|enable_|disable_|register_|deregister_|tag_|untag_)'; then
      deny "shell command contains a mutating boto3 call."
    fi

    # Block role chaining attempts.
    if printf '%s' "$cmd" | grep -E -q 'aws sts (assume-role|get-session-token)'; then
      deny "shell command attempts to escalate via sts (blocked at IAM too — see Layer 1)."
    fi

    # Block profile overrides — model trying to use a different profile.
    if printf '%s' "$cmd" | grep -E -q 'aws .* (--profile|AWS_PROFILE=)[[:space:]=]+(?!kiro-readonly)' \
       || printf '%s' "$cmd" | grep -E -q 'AWS_PROFILE=(?!kiro-readonly)'; then
      deny "shell command sets AWS_PROFILE or --profile to something other than kiro-readonly."
    fi
    ;;

  fs_write|write)
    path="$(printf '%s' "$input" | jq -r '.tool_input.path // empty')"
    content="$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.text // empty')"
    # Don't write to ~/.aws/ from inside the sandbox — that would persist.
    if [[ "$path" == *"/.aws/"* ]]; then
      deny "writes under ~/.aws/ are forbidden."
    fi
    # Warn (don't block) on boto3 writes — the IAM layer will deny mutating calls anyway.
    if printf '%s' "$content" | grep -E -q 'boto3\.Session\(profile_name='; then
      printf '[aws-readonly-guard] notice: file references boto3.Session(profile_name=...). The kiro-readonly profile is the only one available; other profile names will fail with ProfileNotFound.\n' >&2
    fi
    ;;

  '@aws-api-mcp/'*|'@aws-api/'*)
    # If you've installed an AWS API MCP server: gate it the same way.
    op="$(printf '%s' "$input" | jq -r '.tool_input.operation // empty')"
    if [[ -n "$op" ]] && ! [[ "$op" =~ $allowed_aws_verbs ]]; then
      deny "AWS MCP operation '$op' is not on the read-only allow list."
    fi
    ;;

  *)
    exit 0
    ;;
esac

exit 0
```

```bash
chmod +x ~/kiro-home/.kiro/hooks/scripts/aws-readonly-guard.sh
```

### Wire it into every kiro agent

CLI hooks live inside agent JSON (no separate `hooks/` dir for CLI). Add this to the `~/.kiro/agents/*.json` files used inside the sandbox (or to the global `kiro_default` agent override):

```json
"hooks": {
  "preToolUse": [
    {
      "matcher": "*",
      "command": "$HOME/.kiro/hooks/scripts/aws-readonly-guard.sh",
      "timeout_ms": 5000
    }
  ]
}
```

`matcher: "*"` because `preToolUse` is generic — it must inspect `tool_name` and decide.

---

## 6. Layer 4 — agent design discipline

For agents you use inside the sandbox:

- **Reviewers / auditors:** `tools: ["read", "@git"]`. No `shell`, no `use_aws`. The model can't call AWS at all.
- **Builders:** `tools: ["read", "write", "shell"]`. `allowedTools: ["read"]` only — every shell call prompts.
- **Architects with MCP:** `tools: ["read", "@mcp"]`. MCP servers in `mcp.json` should themselves use the kiro-readonly profile.

Don't ship a single agent with `tools: ["*"]` and `allowedTools: ["*"]`. That's a pre-approved blast radius.

---

## 7. Layer 5 — CloudTrail alerting

Even with all the above, you want to know if the model **tried** something. `AccessDenied` events from the `KiroReadOnly` principal are the signal.

```sql
-- CloudWatch Logs Insights (CloudTrail log group)
fields @timestamp, eventName, userIdentity.principalId, errorCode, errorMessage
| filter userIdentity.sessionContext.sessionIssuer.userName = "AWSReservedSSO_KiroReadOnly_*"
| filter errorCode in ["AccessDenied", "UnauthorizedOperation"]
| sort @timestamp desc
| limit 100
```

Alarm on count > 0 per 5 minutes, route to your normal on-call channel. Repeated denies during a kiro session is the model trying to write — useful both as an incident signal and as a coaching signal (steering files need clearer "don't try" rules).

---

## 8. Setup walkthrough (one-shot)

```bash
# Admin (in IAM Identity Center console):
#   1. Create permission set "KiroReadOnly" with the policies in §3.
#   2. Assign to your user in every relevant AWS account.

# You (on the devbox, one time):
sudo apt install bubblewrap jq

mkdir -p ~/kiro-home/.aws ~/kiro-home/.kiro/hooks/scripts ~/bin
# Paste the ~/kiro-home/.aws/config from §4
# Paste ~/bin/kiro-ro from §4
# Paste ~/kiro-home/.kiro/hooks/scripts/aws-readonly-guard.sh from §5
chmod +x ~/bin/kiro-ro ~/kiro-home/.kiro/hooks/scripts/aws-readonly-guard.sh
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc

# Each session:
aws sso login --profile kiro-readonly        # populates ~/kiro-home/.aws/sso/cache/
cd ~/code/some-project
kiro-ro
```

---

## 9. Verification

Ask kiro inside the sandbox to try each of these. Expected results:

| Test | Expected | Why |
|---|---|---|
| `aws s3 ls` | succeeds | `s3:ListAllMyBuckets` is in `ReadOnlyAccess` |
| `aws s3 cp file s3://bucket/key` | hook BLOCKS (`cp` not on allow list) | Layer 3 |
| `aws s3api put-object ...` | hook BLOCKS | Layer 3 |
| `aws secretsmanager get-secret-value ...` | hook ALLOWS, AWS DENIES | Hook only blocks writes; `get-` passes the verb check, but Layer 1 deny statement returns AccessDenied |
| Python script with `boto3.client('s3').delete_object(...)` via execute_bash | hook BLOCKS (boto3 mutating method pattern) | Layer 3 |
| `boto3.Session(profile_name='admin')` written to a `.py` file then run | hook NOTICES on write; runtime fails with `ProfileNotFound` | Layer 2 — `admin` isn't in sandboxed config |
| `aws sts assume-role --role-arn ...admin-role` | hook BLOCKS, AWS would also DENY | Layers 3 + 1 |
| Unsetenv `AWS_PROFILE`, `aws s3 cp ...` | hook BLOCKS the cp; even if it didn't, no other profile is reachable | Layers 3 + 2 |

---

## 10. Honest limitations

- **Hook ordering vs. trust prompt** — kiro's docs do not state whether `preToolUse` fires before or after the per-tool user-confirm dialog. Verify on your installed version: configure a hook that always exits 2 and check whether the prompt appears first.
- **Sandbox network** — `bwrap --share-net` is required for kiro to function. If the model can call AWS APIs, it can also call any other network endpoint. Combine with an egress proxy if your devbox has one.
- **Project files** — anything writable inside the sandbox is at risk. The project directory is intentionally writable. If a project contains creds (it shouldn't), they're reachable.
- **MCP servers** — if you install an AWS-touching MCP server inside the sandboxed `~/.kiro/settings/mcp.json`, it inherits the same env. Verify by running it manually with `AWS_PROFILE=kiro-readonly` and confirming write calls fail.
- **Updates to bwrap policy** — if your distro upgrades bwrap and changes default mount options, re-test the wrapper. The `--bind`/`--ro-bind` semantics have been stable since bwrap 0.4 but worth a smoke check.

---

## 11. References

- Kiro CLI Hooks — <https://kiro.dev/docs/cli/hooks/>
- Kiro CLI built-in tools — <https://kiro.dev/docs/cli/reference/built-in-tools/>
- AWS CLI IAM Identity Center configuration — <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html>
- Boto3 credentials guide — <https://docs.aws.amazon.com/boto3/latest/guide/credentials.html>
- boto3#2403 — explicit `profile_name` overrides `AWS_PROFILE` — <https://github.com/boto/boto3/issues/2403>
- Bubblewrap — <https://github.com/containers/bubblewrap>
- AWS managed policy `ReadOnlyAccess` — <https://docs.aws.amazon.com/aws-managed-policy/latest/reference/ReadOnlyAccess.html>
