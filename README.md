# agent-vscode-copilot-custom-agents

Agent-neutral custom agents for managing files inside the VSCode application-support folder
on macOS (`~/Library/Application Support/Code/`).

One agent per file format. Each lives at `.agents/<name>/AGENT.md` — a self-contained
markdown spec covering **Inspect → Edit → Backup → Clean** for its format, plus hard
rules and worked examples. The `.agents/` layout (not `.claude/`) is intentional: these
specs are runtime-neutral and work with any agent loader that reads structured markdown
+ YAML frontmatter (Claude Code, GitHub Copilot custom chat modes, Cursor agents,
Continue, raw prompt templates, etc.).

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
