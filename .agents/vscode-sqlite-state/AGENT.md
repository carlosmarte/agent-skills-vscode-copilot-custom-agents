---
name: vscode-sqlite-state
description: Inspect, query, and prune the SQLite databases that hold VSCode's persistent state — `User/globalStorage/state.vscdb` (global app state + extension login tokens), `User/workspaceStorage/<hash>/state.vscdb` (per-project open files, terminal history, tree-view expansion), `Cookies` (webview session cookies), and ad-hoc extension `*.db`/`*.sqlite` files. Includes a hash → folder-URI resolver so you can identify which workspace owns which `<hash>` directory before deleting it. **VSCode must be quit first** — these DBs are exclusively locked while VSCode is running. Use when reclaiming disk space, debugging a broken extension's persisted state, finding which projects VSCode remembers, or scrubbing stale workspace entries.
tools: Bash,Read,Write,Edit,Grep,Glob
---

# VSCode SQLite state (`state.vscdb`, `Cookies`, extension DBs)

The persistent state layer. Different from `settings.json` — these are app-managed, schema-versioned SQLite, edited by VSCode itself, never by hand-edit.

## Why

VSCode keeps three flavors of SQLite under the Code folder:

1. **Global** — `User/globalStorage/state.vscdb` is the singleton `ItemTable` of `(key, value)` rows. Login tokens for the GitHub extension, theme last-used, last-opened-folder, and a hundred other singletons live here.
2. **Per-workspace** — `User/workspaceStorage/<hash>/state.vscdb` — one DB per folder you've ever opened. `<hash>` is an MD5 of the folder URI. These accumulate forever; old projects leave dead `<hash>` dirs behind.
3. **Misc** — `Cookies` (Chromium webview session cookies, e.g. for the embedded GitHub login flow), and extension-installed `*.db`/`*.sqlite` files under `User/globalStorage/<extId>/`.

The schema everywhere is the same shape: `ItemTable(key TEXT PRIMARY KEY, value BLOB)`. Values are usually UTF-8 JSON or plain strings.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"

GLOBAL_DB="$BASE/User/globalStorage/state.vscdb"
WS_ROOT="$BASE/User/workspaceStorage"
COOKIES="$BASE/Cookies"

# Profile variants:
# "$BASE/User/profiles/<profile-id>/globalStorage/state.vscdb"
# "$BASE/User/profiles/<profile-id>/workspaceStorage/<hash>/state.vscdb"

# Extension-installed DBs:
ls "$BASE/User/globalStorage/"*/*.db "$BASE/User/globalStorage/"*/*.sqlite 2>/dev/null
```

## Quit VSCode first?

**YES — mandatory.** SQLite uses an exclusive lock; queries against a running VSCode return `database is locked` and abandoned read attempts can leave a `*.vscdb-wal` / `*.vscdb-shm` pair that breaks the DB.

```bash
pgrep -x "Code" >/dev/null && { echo "VSCode is running — quit it first (⌘Q), then retry."; exit 1; }
```

## Inspect

```bash
# 1. Schema check (every state.vscdb has the same ItemTable):
sqlite3 "$GLOBAL_DB" '.tables'                       # → ItemTable
sqlite3 "$GLOBAL_DB" '.schema ItemTable'

# 2. List every key in global state:
sqlite3 "$GLOBAL_DB" "SELECT key FROM ItemTable ORDER BY key;"

# 3. Read one value (extension auth tokens, last-opened folders, etc.):
sqlite3 "$GLOBAL_DB" "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList';" | jq .

# 4. Map every workspace hash to its folder URI:
for d in "$WS_ROOT"/*/; do
  hash=$(basename "$d")
  meta="$d/workspace.json"
  uri="(no workspace.json — likely stale)"
  [[ -f "$meta" ]] && uri=$(jq -r '.folder // .configuration // .workspace // "?"' "$meta")
  printf '%s\t%s\n' "$hash" "$uri"
done | column -t -s $'\t'

# 5. Count per-workspace DB rows (useful to spot bloated workspaces):
for db in "$WS_ROOT"/*/state.vscdb; do
  [[ -f "$db" ]] || continue
  n=$(sqlite3 "$db" "SELECT COUNT(*) FROM ItemTable;" 2>/dev/null)
  size=$(du -h "$db" | cut -f1)
  printf '%s\t%s rows\t%s\n' "$(basename "$(dirname "$db")")" "$n" "$size"
done | sort -k3 -h -r | head -20

# 6. Cookies (webview session) — just the host list, never the values:
sqlite3 "$COOKIES" "SELECT host_key, name FROM cookies;" 2>/dev/null
```

## Edit

Default to read-only. Mutation requires explicit intent and a backup.

```bash
# Delete one key (e.g. clear a corrupted extension state):
cp "$GLOBAL_DB" "$GLOBAL_DB.bak.$(date -u +%Y%m%dT%H%M%SZ)"
sqlite3 "$GLOBAL_DB" "DELETE FROM ItemTable WHERE key = 'some.extension.cachedThing';"

# Replace a value (rare — usually you should clear and let the extension repopulate):
sqlite3 "$GLOBAL_DB" "UPDATE ItemTable SET value = ? WHERE key = ?;" "$NEW_VALUE" "$KEY"

# Vacuum to reclaim space after large deletes:
sqlite3 "$GLOBAL_DB" "VACUUM;"
```

## Backup

Always before any mutation, including `VACUUM`:

```bash
cp "$GLOBAL_DB" "$GLOBAL_DB.bak.$(date -u +%Y%m%dT%H%M%SZ)"
# For per-workspace, back up the whole hash dir (preserves workspace.json metadata):
cp -R "$WS_ROOT/<hash>" "$WS_ROOT/<hash>.bak.$(date -u +%Y%m%dT%H%M%SZ)"
```

## Clean / Prune

The big win is pruning `workspaceStorage/<hash>/` directories whose folder no longer exists on disk:

```bash
# Dry run — identify stale workspaces:
for d in "$WS_ROOT"/*/; do
  meta="$d/workspace.json"
  [[ -f "$meta" ]] || { echo "STALE (no workspace.json) $d"; continue; }
  uri=$(jq -r '.folder // empty' "$meta")
  [[ -z "$uri" ]] && continue
  path="${uri#file://}"
  [[ -d "$path" ]] || echo "STALE (folder gone) $d  →  was: $path"
done

# Apply (after reviewing the list above):
for d in "$WS_ROOT"/*/; do
  meta="$d/workspace.json"
  uri=$(jq -r '.folder // empty' "$meta" 2>/dev/null)
  path="${uri#file://}"
  if [[ ! -f "$meta" ]] || { [[ -n "$path" ]] && [[ ! -d "$path" ]]; }; then
    cp -R "$d" "$d.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    rm -rf "$d"
  fi
done

# Vacuum the global DB after extension uninstalls:
sqlite3 "$GLOBAL_DB" "VACUUM;"
```

## Hard rules

- **VSCode must be quit.** A running VSCode holds an exclusive lock; queries either fail or leave WAL/SHM corruption.
- **Never edit `Cookies` by hand.** Webview auth state lives there; rewriting it logs the user out of every embedded service. Delete the whole file if you must reset.
- **Never `DROP TABLE ItemTable`.** Replace specific keys; the table itself is part of the schema VSCode expects.
- **Token values are credentials.** Treat `globalStorage/state.vscdb` as secret material — never commit, never paste into logs, never share a copy.
- **Don't delete `<hash>` dirs while VSCode is open.** It will write a new copy on shutdown and you'll undo your work.

## Examples

### 1. Find which workspace has the largest DB

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }
for db in "$WS_ROOT"/*/state.vscdb; do
  printf '%s\t%s\n' "$(du -k "$db" | cut -f1)" "$db"
done | sort -nr | head -5
```

### 2. List recently opened folders globally

```bash
sqlite3 "$GLOBAL_DB" "SELECT value FROM ItemTable WHERE key='history.recentlyOpenedPathsList';" \
  | jq -r '.entries[].folderUri // .entries[].fileUri'
```

### 3. Reset a stuck extension's persisted state

```bash
ext="ms-python.python"
cp "$GLOBAL_DB" "$GLOBAL_DB.bak.$(date -u +%Y%m%dT%H%M%SZ)"
sqlite3 "$GLOBAL_DB" "DELETE FROM ItemTable WHERE key LIKE '${ext}%';"
```
