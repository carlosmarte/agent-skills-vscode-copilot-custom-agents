---
name: vscode-leveldb
description: Inspect LevelDB key-value stores used by VSCode's Chromium layer for browser-style web storage — `Local Storage/leveldb/` (persistent UI state per origin), `Session Storage/` (per-window UI state cleared on quit), and `User/globalStorage/<extId>/` directories when an extension chose LevelDB over SQLite. **VSCode must be quit first** — LevelDB requires an exclusive file lock. Use when debugging UI state that won't reset, recovering panel/layout settings, or reclaiming space from a runaway extension's persisted blobs. `Session Storage/` is safe to delete and VSCode will rebuild it; `Local Storage/leveldb/` deletion resets panel widths, theme toggles, and similar UI niceties.
tools: Bash,Read,Write,Edit,Grep,Glob
---

# VSCode LevelDB stores (`Local Storage/`, `Session Storage/`, extension leveldb dirs)

LevelDB is Google's embedded key-value store. VSCode inherits it from Chromium and uses it everywhere a browser would use Web Storage.

## Why

LevelDB is **not** SQLite — it's a directory of `.ldb`, `.log`, `MANIFEST-*`, `CURRENT`, and `LOCK` files. There is no `sqlite3` equivalent CLI shipped with macOS; reading requires Node, Python, Go, or the `leveldb` Homebrew formula. The format is binary; key/value pairs are arbitrary byte strings (often UTF-16-encoded JSON for VSCode's UI state).

Three locations matter:

- `Local Storage/leveldb/` — persistent UI state (panel widths, sidebar toggles, "last theme used", recently-used find queries). Survives quit.
- `Session Storage/` — per-window transient UI state. Cleared by VSCode itself on quit; safe to delete.
- `User/globalStorage/<extension-id>/` — when an extension picks LevelDB (rarer than SQLite). Identifiable by the presence of `LOCK`, `CURRENT`, `*.ldb`.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"

LS_DIR="$BASE/Local Storage/leveldb"
SS_DIR="$BASE/Session Storage"

# Find every extension that uses LevelDB:
find "$BASE/User/globalStorage" -name CURRENT -type f 2>/dev/null | xargs -n1 dirname
```

## Quit VSCode first?

**YES — mandatory.** LevelDB writes a `LOCK` file at the directory root; if VSCode is running, the lock is held and any reader (including yours) will either block or report `IO error: lock leveldb/LOCK`.

```bash
pgrep -x "Code" >/dev/null && { echo "VSCode is running — quit it first (⌘Q), then retry."; exit 1; }
```

## Inspect

Three viable readers, pick one:

### Option A — Node (no install if you have npm)

```bash
# One-shot, requires `npm i -g level` or runs in a scratch dir:
mkdir -p /tmp/leveldb-reader && cd /tmp/leveldb-reader
[[ -d node_modules/level ]] || npm i level >/dev/null 2>&1
node -e "
  const { Level } = require('level');
  const db = new Level(process.argv[1], { keyEncoding: 'utf8', valueEncoding: 'utf8' });
  (async () => {
    for await (const [k, v] of db.iterator()) {
      console.log(k, '=>', v.slice(0, 200));
    }
    await db.close();
  })().catch(e => { console.error(e.message); process.exit(1); });
" "$LS_DIR"
```

### Option B — Python (`plyvel`)

```bash
pip install --user plyvel >/dev/null 2>&1
python3 - <<'PY' "$LS_DIR"
import plyvel, sys
db = plyvel.DB(sys.argv[1], create_if_missing=False)
try:
    for k, v in db:
        print(k[:80].decode('utf-8', 'replace'), '=>', v[:200].decode('utf-16-le', 'replace'))
finally:
    db.close()
PY
```

### Option C — Homebrew `leveldb` (CLI binaries are minimal; mostly for `ldb` dump)

```bash
brew install leveldb
# ldb is not always shipped; the `leveldbutil` binary supports dump:
# leveldbutil dump "$LS_DIR/000003.log"
```

### Quick size-only inspection (no decode required)

```bash
du -sh "$LS_DIR" "$SS_DIR"
find "$BASE/User/globalStorage" -name CURRENT -type f 2>/dev/null \
  | while read f; do dir=$(dirname "$f"); printf '%s\t%s\n' "$(du -sh "$dir" | cut -f1)" "$dir"; done | sort -h
```

## Edit

**Inspect-only by policy.** Hand-mutating LevelDB blobs from outside Chromium will likely corrupt the value-encoding contract (UTF-16-LE with length prefixes) that the renderer expects.

If you must reset a specific key, the safer move is **delete the whole store** and let VSCode rebuild defaults:

```bash
cp -R "$LS_DIR" "$LS_DIR.bak.$(date -u +%Y%m%dT%H%M%SZ)"
rm -rf "$LS_DIR"
# Next launch: VSCode rebuilds, but you lose panel widths / theme state / sidebar layout.
```

## Backup

Always copy the **whole directory** — LevelDB is multi-file and `MANIFEST-*` / `CURRENT` / `*.ldb` must stay consistent:

```bash
cp -R "$LS_DIR" "$LS_DIR.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -R "$SS_DIR" "$SS_DIR.bak.$(date -u +%Y%m%dT%H%M%SZ)"
```

## Clean / Prune

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }

# Session Storage — always safe to delete; rebuilt on next launch:
rm -rf "$SS_DIR"

# Local Storage — resets UI niceties; back up first, then delete:
cp -R "$LS_DIR" "$LS_DIR.bak.$(date -u +%Y%m%dT%H%M%SZ)"
rm -rf "$LS_DIR"

# Extension LevelDB dirs — only delete the one belonging to the misbehaving extension:
ext_dir="$BASE/User/globalStorage/some.extension.id"
[[ -f "$ext_dir/CURRENT" ]] && {
  cp -R "$ext_dir" "$ext_dir.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  rm -rf "$ext_dir"
}
```

## Hard rules

- **Never copy individual files** out of a LevelDB dir — copy the whole directory. `MANIFEST-*` points at `*.ldb` files by name; a partial copy is broken.
- **Never edit `LOCK`, `CURRENT`, or `MANIFEST-*` by hand.** They are part of LevelDB's recovery protocol.
- **VSCode must be quit.** No exception. A running VSCode will undo your delete on shutdown by writing fresh files.
- **Treat `Local Storage/leveldb/` values as opaque.** They are UTF-16-LE with binary length prefixes; do not grep them as if they were UTF-8.

## Examples

### 1. Find which LevelDB directory is bloating disk

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }
find "$BASE" -name CURRENT -type f 2>/dev/null \
  | while read f; do dir=$(dirname "$f"); printf '%s\t%s\n' "$(du -sh "$dir" | cut -f1)" "$dir"; done \
  | sort -h | tail -10
```

### 2. Reset a single extension's LevelDB state

```bash
ext_dir="$BASE/User/globalStorage/dbaeumer.vscode-eslint"
[[ -f "$ext_dir/CURRENT" ]] || { echo "Not a LevelDB store"; exit 1; }
cp -R "$ext_dir" "$ext_dir.bak.$(date -u +%Y%m%dT%H%M%SZ)"
rm -rf "$ext_dir"
```

### 3. Reclaim space by clearing Session Storage

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }
du -sh "$SS_DIR"
rm -rf "$SS_DIR"
echo "rebuilt on next launch"
```
