# Install kiro CLI on Linux + use this catalog

## 1. Install kiro CLI

Official installer (Linux x86_64):

```bash
curl -fsSL https://desktop-release.kiro.dev/latest/kirocli-installer-linux-x64.sh | bash
```

For systems with `glibc < 2.34`, use the musl variant — see
<https://kiro.dev/docs/cli/installation/>.

Verify:

```bash
kiro-cli --version
kiro-cli --help
```

The binary lands at `~/.local/bin/kiro-cli`. Make sure that's on your
`PATH`.

## 2. First-run config

`~/.kiro/` is created on first launch. Sign in (the CLI walks you through
AWS Builder ID or Identity Center).

```bash
kiro-cli login
```

## 3. Clone this catalog

```bash
mkdir -p ~/code
git clone git@github.com:weclaudecode/kiro.git ~/code/kiro
cd ~/code/kiro
```

## 4. Install artifacts

List what's available and where it would go (with the global scope):

```bash
./scripts/list.sh
```

Walk the catalog interactively (default scope: global → `~/.kiro/`):

```bash
./scripts/install.sh
```

The script asks `Y/N` per artifact. Defaults to N. To preview without
writing:

```bash
./scripts/install.sh --dry-run
```

To install the always-on steering files non-interactively:

```bash
./scripts/install.sh --yes-to 'steering/*'
```

To install into a specific project's `.kiro/` instead of global:

```bash
./scripts/install.sh --scope project ~/code/some-project
```

## 5. Populate secrets

The `mcp.sample.json` uses `${ENV_VAR}` placeholders. Set them via either:

- **Project scope:** `direnv` + a gitignored `.envrc` per project.
- **Cross-project:** `~/.config/claude/secrets.env` (`chmod 600`), sourced
  from your `~/.zshrc` or `~/.bashrc`.

See `mcp-guide.md` for the variable list per server.

## 6. Verify

```bash
kiro-cli            # opens the chat
/agent              # should list installed agents
/tools              # should show MCP tools if mcp.json was installed
```

In a fresh shell so the env vars are picked up.

## Updating the catalog later

```bash
cd ~/code/kiro
git pull
./scripts/install.sh             # re-walk; existing files are flagged "EXISTS, will overwrite"
```

`install.sh` always asks before overwriting.
