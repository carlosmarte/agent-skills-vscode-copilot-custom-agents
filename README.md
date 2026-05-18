# agent-vscode-copilot-custom-agents

Agent-neutral custom agents for managing files inside the VSCode application-support folder
on macOS (`~/Library/Application Support/Code/`).

One agent per file format. Each lives at `.agents/<name>/AGENT.md` — a self-contained
markdown spec covering **Inspect → Edit → Backup → Clean** for its format, plus hard
rules and worked examples. The `.agents/` layout (not `.claude/`) is intentional: these
specs are runtime-neutral and work with any agent loader that reads structured markdown
+ YAML frontmatter (Claude Code, GitHub Copilot custom chat modes, Cursor agents,
Continue, raw prompt templates, etc.).

## Install & Update Script

To install or update the `symlink-agents` helper (an interactive picker that
redirects VSCode's `User/prompts/` to a managed `~/agents/` folder via symlink),
run one of the following from your terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash
```

```sh
wget -qO- https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash
```

The installer drops `symlink-agents` into `~/.local/bin/` and prints next steps.
Pass flags after `-s --` to customize:

```sh
# install + run the interactive picker immediately
curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash -s -- --run

# install to a different prefix
curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash -s -- --prefix=/usr/local/bin

# pin to a specific tag / branch / commit
curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash -s -- --ref=v0.1.0
```

Equivalent env vars: `AGENTS_PREFIX`, `AGENTS_REF`, `AGENTS_RUN=1`.

Once installed, `symlink-agents` offers a menu to:

1. Create your preferred folder (default `~/agents`)
2. Move any existing prompts from VSCode's directory into it
3. Backup the original VSCode prompts folder as `prompts_bk.<UTC-ts>` and remove it
4. Create the symlink

Every step is idempotent and re-runnable. Run `symlink-agents --status` any
time to see the current state, or `symlink-agents --all` to run all four steps
non-interactively.

## Agents

| Agent | File format / location | Edit? | Clean? | Quit VSCode first? |
| ----- | ---------------------- | ----- | ------ | ------------------ |
| [`vscode-jsonc-config`](.agents/vscode-jsonc-config/AGENT.md) | `User/settings.json`, `User/keybindings.json`, `argv.json` (JSONC) | yes | no | no |
| [`vscode-snippets`](.agents/vscode-snippets/AGENT.md) | `User/snippets/*.code-snippets`, `User/snippets/*.json` | yes | yes | no |
| [`vscode-sqlite-state`](.agents/vscode-sqlite-state/AGENT.md) | `state.vscdb` (global + workspace), `Cookies`, extension `*.db`/`*.sqlite` | yes (with care) | yes (per-workspace prune) | **yes** |
| [`vscode-leveldb`](.agents/vscode-leveldb/AGENT.md) | `Local Storage/leveldb/`, `Session Storage/`, ext LevelDB dirs | inspect only | Session Storage yes | **yes** |
| [`vscode-chromium-cache`](.agents/vscode-chromium-cache/AGENT.md) | `Cache/`, `CachedData/`, `Code Cache/`, `GPUCache/`, Dawn caches | no | yes (safe-delete) | **yes** |
| [`vscode-logs`](.agents/vscode-logs/AGENT.md) | `logs/<sessionId>/*.log` | no | yes (prune by age) | no |
| [`vscode-history`](.agents/vscode-history/AGENT.md) | `User/History/<hash>/` + `entries.json` | restore only | yes (orphans + age) | no |
| [`vscode-bdic-dictionaries`](.agents/vscode-bdic-dictionaries/AGENT.md) | `Dictionaries/*.bdic` | replace only | yes (unused locales) | no |
| [`vscode-app-managed-json`](.agents/vscode-app-managed-json/AGENT.md) | `Machine/`, `rapid_render.json`, `Crashpad/`, singleton lockfiles | **read-only** | singletons only | depends |

## File shape

Every `AGENT.md` follows the same shape:

```markdown
---
name: <kebab-case>
description: <when to invoke, what it does, trigger keywords, prerequisites>
tools: Bash,Read,Write,Edit,Grep,Glob
---

# Title

Why → Location → Quit VSCode first? → Inspect → Edit → Backup → Clean → Hard rules → Examples
```

`tools:` is advisory — it lists the shell/file capabilities the agent expects to have
available. Runtimes that don't recognize the field will ignore it; runtimes that do
(Claude Code, etc.) can use it to gate execution.

## Loading these into an agent runtime

### Claude Code

Symlink each into `~/.claude/skills/<name>` (Claude Code reads `SKILL.md` by default,
so create a `SKILL.md` symlink pointing at `AGENT.md`):

```bash
REPO="$(pwd)"
for d in "$REPO"/.agents/*/; do
  name=$(basename "$d")
  mkdir -p "$HOME/.claude/skills/$name"
  ln -sf "$d/AGENT.md" "$HOME/.claude/skills/$name/SKILL.md"
done
```

### GitHub Copilot (VSCode custom chat modes)

Each `AGENT.md` is already in the right shape — copy or symlink into
`.github/chatmodes/<name>.chatmode.md` of the consuming repo, or into
`~/Library/Application Support/Code/User/prompts/` for a global mode.

### Other runtimes / raw prompts

Just `cat .agents/<name>/AGENT.md` and feed it as a system prompt. The frontmatter
is plain YAML; the body is plain Markdown.

## Conventions used across every agent

- **Path**: `BASE="$HOME/Library/Application Support/Code"`. Insiders variant uses `"Code - Insiders"`. Profile variants live under `"$BASE/User/profiles/<profile-id>/"`.
- **Backup naming**: `<file>.bak.$(date -u +%Y%m%dT%H%M%SZ)` placed next to the original. Never inside a hashed dir VSCode scans.
- **Quit-VSCode check** (for agents that need it): `pgrep -x "Code" >/dev/null && { echo "VSCode is running — quit it first"; exit 1; }`.
- **Never commit `User/` to a source repo.** It is per-machine and often contains tokens.

## Decision guide — which agent to use when

- **Editor is sluggish, taking up disk** → `vscode-chromium-cache` (safe-delete), then `vscode-logs` (prune), then `vscode-history` (prune orphans).
- **Setting won't take effect / want to add a setting** → `vscode-jsonc-config`.
- **Extension state is corrupted / login token stuck** → `vscode-sqlite-state` (clear specific keys from global state).
- **UI panel widths / sidebar layout broken** → `vscode-leveldb` (clear `Local Storage/leveldb/`).
- **Spell-check showing wrong language / dictionaries eating disk** → `vscode-bdic-dictionaries`.
- **Need to recover an unsaved file** → `vscode-history`.
- **Custom snippet auditing / prefix collision** → `vscode-snippets`.
- **Diagnosing a crash or extension activation failure** → `vscode-logs`.
- **Curiosity about what VSCode itself persists** → `vscode-app-managed-json` (read-only).

### Persistent Configuration File

If you want to permanently hardcode your preferred model without having to set flags or environment variables, you can edit the Copilot CLI configuration file directly.

- Open (or create) `~/.copilot/config.json` (or the equivalent `.copilot/config.json` in your project directory).
- Add the `default_model` key:

JSON
```
`{ "default_model": "gpt-5" } `
```

### Disable Specific MCP Servers (CLI Flag)

If you have custom servers set up (like Playwright, Azure, or Git) and want to exclude specific ones at runtime, use:

Bash
```
`copilot --disable-mcp-server <ServerName> `
```

*(e.g., `copilot --disable-mcp-server Playwright --disable-mcp-server ADO`)*

### A Note on Configs

You don't need to pass `/dev/null` for an empty config. If you want a persistent setup that doesn't load any external servers by default, you can simply use an empty JSON object in your MCP config file (`~/.copilot/mcp-config.json`):

JSON
```
`{ "mcpServers": {} } `
```

*(Also, as of recent CLI versions, you can interactively run `/mcp disable <server-name>` inside the Copilot CLI, and it will persistently disable it across sessions).*
