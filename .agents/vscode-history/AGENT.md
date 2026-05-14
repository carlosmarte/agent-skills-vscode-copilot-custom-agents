---
name: vscode-history
description: Search, restore from, and prune VSCode's built-in Local History — per-edit snapshots saved under `User/History/<hash>/`, indexed by `entries.json`, used to recover unsaved or pre-Git-commit changes. Use when a file was lost or overwritten and Git can't help (it was never committed), or to prune the History tree when it has grown to GB-scale. Each `<hash>` directory holds snapshots of one file; `entries.json` maps numeric snapshot IDs back to the source path and timestamp. VSCode does not need to be quit — History is append-only and resilient to concurrent access.
tools: Bash,Read,Write,Edit,Grep,Glob
---

# VSCode Local History (`User/History/<hash>/`)

The "I forgot to commit" safety net. Per-edit snapshots automatically captured by VSCode.

## Why

Whenever you save a file, VSCode writes a copy under `User/History/<hash>/<numeric-id>.<ext>` and appends a row to `User/History/<hash>/entries.json`:

```json
{
  "version": 1,
  "resource": "file://$HOME/work/repo/src/foo.ts",
  "entries": [
    { "id": "abc123.ts", "source": "Manual save", "timestamp": 1715600000000 },
    { "id": "def456.ts", "source": "File saved",  "timestamp": 1715600300000 }
  ]
}
```

`<hash>` is a deterministic hash of the absolute file path. The numeric IDs are not sequential — they're random 8-char hex/base32 tokens with the original file extension preserved.

Local History is **per-file, not per-folder**. There's no "git status" equivalent across the tree, but you can grep the `entries.json` files to map back to which paths still have history.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"
HIST="$BASE/User/History"

# Profile variants:
# "$BASE/User/profiles/<profile-id>/History/"
```

## Quit VSCode first?

**No.** Reads are safe; restores write a new file outside `History/` so no lock contention.

## Inspect

```bash
# 1. Total disk used by History:
du -sh "$HIST"
ls "$HIST" | wc -l   # number of files VSCode is tracking

# 2. Find which path a <hash> represents:
hash="abc1234567890abc"
jq -r '.resource' "$HIST/$hash/entries.json" 2>/dev/null

# 3. Reverse lookup — given a file path, find its history dir:
TARGET="file://$HOME/work/repo/src/foo.ts"
grep -l "\"resource\":\"$TARGET\"" "$HIST"/*/entries.json | xargs -n1 dirname

# 4. Filename-substring search across ALL tracked files:
grep -l '"resource":.*foo.ts' "$HIST"/*/entries.json | while read f; do
  dir=$(dirname "$f")
  uri=$(jq -r '.resource' "$f")
  n=$(jq '.entries | length' "$f")
  printf '%s\t%d snapshots\t%s\n' "$(basename "$dir")" "$n" "$uri"
done

# 5. List snapshots for one file, newest first:
hash="abc1234567890abc"
jq -r '.entries | sort_by(-.timestamp) | .[] | "\(.timestamp)\t\(.id)\t\(.source)"' "$HIST/$hash/entries.json" \
  | while IFS=$'\t' read ts id src; do
      printf '%s\t%s\t%s\n' "$(date -r $((ts/1000)) +%Y-%m-%dT%H:%M:%S)" "$id" "$src"
    done

# 6. Full-text grep across all snapshots for a known content fragment:
grep -rIln 'TODO: refactor this' "$HIST"
```

## Edit

Local History is **restore-from only** — you don't edit snapshots, you copy one back over the original.

### Restore one snapshot

```bash
hash="abc1234567890abc"
snapshot_id="def45678.ts"

# Resolve the original path:
uri=$(jq -r '.resource' "$HIST/$hash/entries.json")
orig="${uri#file://}"

# Back up whatever is currently at the destination:
[[ -f "$orig" ]] && cp "$orig" "$orig.bak.$(date -u +%Y%m%dT%H%M%SZ)"

# Copy the snapshot in:
cp "$HIST/$hash/$snapshot_id" "$orig"
echo "Restored $orig from snapshot $snapshot_id"
```

### Diff a snapshot against the current file

```bash
diff -u "$HIST/$hash/$snapshot_id" "$orig" | less
```

## Backup

If you're about to prune aggressively, archive first:

```bash
tar -czf "$HOME/Desktop/vscode-history-$(date -u +%Y%m%dT%H%M%SZ).tgz" -C "$BASE/User" History
```

## Clean / Prune

History grows monotonically. VSCode caps per-file snapshot count via `workbench.localHistory.maxFileEntries` (default 50), but old `<hash>` dirs for deleted files are kept forever.

```bash
# Inspect:
du -sh "$HIST"
ls "$HIST" | wc -l

# 1. Prune entire <hash> dirs whose source file no longer exists:
#    Dry run first:
for d in "$HIST"/*/; do
  meta="$d/entries.json"
  [[ -f "$meta" ]] || { echo "ORPHAN (no entries.json) $d"; continue; }
  uri=$(jq -r '.resource' "$meta")
  path="${uri#file://}"
  [[ -f "$path" ]] || echo "ORPHAN (file gone) $d  →  was: $path"
done

# Apply (after review):
for d in "$HIST"/*/; do
  meta="$d/entries.json"
  if [[ ! -f "$meta" ]]; then rm -rf "$d"; continue; fi
  uri=$(jq -r '.resource' "$meta")
  path="${uri#file://}"
  [[ -n "$path" ]] && [[ ! -f "$path" ]] && rm -rf "$d"
done

# 2. Prune by age — drop dirs untouched in 60+ days:
find "$HIST" -mindepth 1 -maxdepth 1 -type d -mtime +60 -print
find "$HIST" -mindepth 1 -maxdepth 1 -type d -mtime +60 -exec rm -rf {} +

# 3. Per-file snapshot cap (does not require an extension):
#    Keep only the 10 newest snapshots per file:
for d in "$HIST"/*/; do
  meta="$d/entries.json"
  [[ -f "$meta" ]] || continue
  keep=$(jq -r '.entries | sort_by(-.timestamp) | .[0:10] | .[].id' "$meta")
  for snap in "$d"/*; do
    [[ "$(basename "$snap")" == "entries.json" ]] && continue
    grep -q "$(basename "$snap")" <<<"$keep" || rm -f "$snap"
  done
  # Rewrite entries.json to match what survived:
  cp "$meta" "$meta.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  jq '.entries |= sort_by(-.timestamp) | .entries |= .[0:10]' "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
done
```

## Hard rules

- **`entries.json` must stay in sync with the snapshot files.** Deleting snapshot files without rewriting `entries.json` leaves a dangling reference that VSCode will surface as "snapshot missing" in the Timeline view.
- **Don't restore over a file with uncommitted Git changes** without backing it up first — Local History is for "before VSCode saved", not "before Git committed". You can lose unrelated edits.
- **Local History is per-machine.** It is not synced via Settings Sync. Don't rely on it across machines.
- **The `<hash>` is NOT MD5 of the path** (it's an internal hashing scheme); don't try to compute it yourself — always look up via `entries.json`.

## Examples

### 1. Recover a file you deleted from disk an hour ago

```bash
HIST="$HOME/Library/Application Support/Code/User/History"
# Search by filename:
grep -l '"resource":.*lost-file.ts' "$HIST"/*/entries.json | while read f; do
  dir=$(dirname "$f")
  echo "Found history at: $dir"
  jq -r '.entries | sort_by(-.timestamp) | .[0] | "Latest snapshot: \(.id) at \(.timestamp)"' "$f"
done
```

### 2. Find every file you've touched in the last 24 hours

```bash
HIST="$HOME/Library/Application Support/Code/User/History"
cutoff=$(( ($(date +%s) - 86400) * 1000 ))
for f in "$HIST"/*/entries.json; do
  recent=$(jq --argjson c "$cutoff" '.entries | map(select(.timestamp > $c)) | length' "$f")
  (( recent > 0 )) && echo "$recent recent snapshots  $(jq -r '.resource' "$f")"
done
```

### 3. Reclaim space by pruning orphans + old snapshots

```bash
HIST="$HOME/Library/Application Support/Code/User/History"
du -sh "$HIST"
# orphans:
for d in "$HIST"/*/; do
  uri=$(jq -r '.resource' "$d/entries.json" 2>/dev/null)
  path="${uri#file://}"
  [[ -n "$path" ]] && [[ ! -f "$path" ]] && rm -rf "$d"
done
# 60-day expiry:
find "$HIST" -mindepth 1 -maxdepth 1 -type d -mtime +60 -exec rm -rf {} +
du -sh "$HIST"
```
