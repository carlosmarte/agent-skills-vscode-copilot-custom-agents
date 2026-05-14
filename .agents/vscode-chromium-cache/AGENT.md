---
name: vscode-chromium-cache
description: Safely delete VSCode's Chromium/Electron binary cache directories — `Cache/`, `CachedData/`, `Code Cache/`, `GPUCache/`, `DawnGraphiteCache/`, `DawnWebGPUCache/` — to reclaim disk space when VSCode feels sluggish or has accumulated multi-GB caches. These directories hold compiled V8 bytecode, HTTP cache, GPU shader cache, and Dawn (WebGPU) compiled pipelines; all are regenerated automatically on next launch. **VSCode must be quit first** or mmap'd pages won't actually free disk space. No edit path — caches are opaque binary blobs. Use when troubleshooting a misbehaving editor, freeing disk space, or as a quarterly hygiene sweep.
tools: Bash,Read,Grep,Glob
---

# VSCode Chromium / Electron caches

The "browser engine" caches. None are user data; all are reproducible.

## Why

Because VSCode is Electron, it inherits Chromium's caching layers wholesale:

| Directory | What it holds | Typical size | Safe to delete? |
| --------- | ------------- | ------------ | --------------- |
| `Cache/` | HTTP cache for extension marketplace, telemetry, webview fetches | 50–500 MB | **Yes** |
| `CachedData/` | V8-compiled JS bytecode (`*.code` files matched to VSCode build) | 100–800 MB | **Yes** |
| `Code Cache/js/` | Renderer V8 code cache | 50–200 MB | **Yes** |
| `Code Cache/wasm/` | WebAssembly compile cache | 10–100 MB | **Yes** |
| `GPUCache/` | Skia/ANGLE GPU shader cache | 10–50 MB | **Yes** |
| `DawnGraphiteCache/` | Dawn (WebGPU) Graphite backend cache | 1–20 MB | **Yes** |
| `DawnWebGPUCache/` | Dawn WebGPU pipeline cache | 1–20 MB | **Yes** |
| `Service Worker/CacheStorage/` | Webview service workers (if any extension uses them) | 0–100 MB | Yes |
| `IndexedDB/` | Webview IndexedDB stores | 0–50 MB | Usually yes — but check first; some extensions store user state here |

Every entry above is rebuilt on first launch after deletion. First launch is slower (V8 must recompile bytecode), subsequent launches return to normal speed.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"

CACHE_DIRS=(
  "$BASE/Cache"
  "$BASE/CachedData"
  "$BASE/Code Cache"
  "$BASE/GPUCache"
  "$BASE/DawnGraphiteCache"
  "$BASE/DawnWebGPUCache"
)
# Optional, only delete after manual review:
MAYBE_DIRS=(
  "$BASE/Service Worker/CacheStorage"
  "$BASE/IndexedDB"
)
```

## Quit VSCode first?

**YES — mandatory** for the space to actually free. macOS keeps deleted-but-mmap'd files alive until the process unmaps them. With VSCode running, `rm -rf` succeeds but disk usage drops only on next quit.

```bash
pgrep -x "Code" >/dev/null && { echo "VSCode is running — quit it first (⌘Q), then retry."; exit 1; }
```

## Inspect

Just measure — there's nothing readable inside:

```bash
# Per-directory size:
for d in "${CACHE_DIRS[@]}" "${MAYBE_DIRS[@]}"; do
  [[ -d "$d" ]] && du -sh "$d"
done

# Total reclaim potential:
du -ch "${CACHE_DIRS[@]}" 2>/dev/null | tail -1

# File-count sanity check (an empty CachedData with thousands of zero-byte files
# means a prior interrupted purge — clean it again):
for d in "${CACHE_DIRS[@]}"; do
  [[ -d "$d" ]] && printf '%s\t%s files\n' "$d" "$(find "$d" -type f | wc -l | tr -d ' ')"
done
```

## Edit

**No edit path.** Files are Chromium-internal binary formats with embedded checksums. Hand-editing produces a cache miss at best, a crash at worst.

## Backup

Backups are almost never useful here (caches regenerate), but if you want a sanity copy:

```bash
# Optional — only the first time you do this:
mkdir -p "$BASE.cache-backup.$(date -u +%Y%m%dT%H%M%SZ)"
mv "${CACHE_DIRS[@]}" "$BASE.cache-backup.$(date -u +%Y%m%dT%H%M%SZ)/" 2>/dev/null
```

In practice, **just delete**. If something breaks, reinstalling VSCode also resets these.

## Clean / Prune

The canonical recipe:

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }

echo "Before:"
du -sh "${CACHE_DIRS[@]}" 2>/dev/null
total_before=$(du -sk "${CACHE_DIRS[@]}" 2>/dev/null | awk '{s+=$1}END{print s}')

for d in "${CACHE_DIRS[@]}"; do
  [[ -d "$d" ]] && rm -rf "$d"
done

echo "After:"
total_after=0
for d in "${CACHE_DIRS[@]}"; do [[ -d "$d" ]] && total_after=$((total_after + $(du -sk "$d" | cut -f1))); done
echo "Reclaimed: $(( (total_before - total_after) / 1024 )) MB"
```

### Aggressive (also clear webview storage)

Only do this if you're certain no installed extension uses IndexedDB for user state:

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }
rm -rf "${CACHE_DIRS[@]}" "${MAYBE_DIRS[@]}"
```

### Single-dir surgical clear

When sluggishness is GPU-related:

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }
rm -rf "$BASE/GPUCache" "$BASE/DawnGraphiteCache" "$BASE/DawnWebGPUCache"
```

## Hard rules

- **VSCode must be quit.** Otherwise mmap holds the pages and you see no disk reclaim until next launch.
- **Never delete `User/`, `globalStorage/`, `workspaceStorage/`, `logs/`, or `History/` as part of "cache cleaning".** Those are user data — use the dedicated skills (`vscode-jsonc-config`, `vscode-sqlite-state`, `vscode-logs`, `vscode-history`).
- **Don't shell-quote `Code Cache` as `"Code\ Cache"`** — the directory name contains a space; use `"Code Cache"` with double quotes consistently.
- **Don't delete `Crashpad/`** — that's not a cache, that's crash-report state. Removing it loses diagnostic info if VSCode crashes.

## Examples

### 1. One-shot quarterly cleanup

```bash
pgrep -x Code >/dev/null && { echo quit VSCode first; exit 1; }
BASE="$HOME/Library/Application Support/Code"
du -sh "$BASE/Cache" "$BASE/CachedData" "$BASE/Code Cache" "$BASE/GPUCache" "$BASE/DawnGraphiteCache" "$BASE/DawnWebGPUCache" 2>/dev/null
rm -rf "$BASE/Cache" "$BASE/CachedData" "$BASE/Code Cache" "$BASE/GPUCache" "$BASE/DawnGraphiteCache" "$BASE/DawnWebGPUCache"
echo done
```

### 2. Inspect without deleting

```bash
BASE="$HOME/Library/Application Support/Code"
for d in "$BASE/Cache" "$BASE/CachedData" "$BASE/Code Cache" "$BASE/GPUCache"; do
  [[ -d "$d" ]] && du -sh "$d"
done
```

### 3. Diagnose "first launch after cache clear is slow"

That's expected. V8 must recompile JS bytecode and rebuild the HTTP cache. Time it once; the second launch should match pre-clear speed:

```bash
time /usr/bin/open -nW -a "Visual Studio Code"
# Quit (⌘Q), then:
time /usr/bin/open -nW -a "Visual Studio Code"
# Second number ≈ first number minus ~3-10s == cache rebuild cost.
```
