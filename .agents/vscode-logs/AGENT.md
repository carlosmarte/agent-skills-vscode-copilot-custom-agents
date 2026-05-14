---
name: vscode-logs
description: Tail, search, and prune VSCode's plain-text log files under `logs/<sessionId>/` — main process, renderer (per window), shared process, and extension-host logs. Use when diagnosing a crash, a slow startup, a failing extension activation, or a webview that won't load. Includes a session-map (which log file = which subsystem) and an age-based prune (`logs/<sessionId>/` directories accumulate one per launch, never auto-cleaned by VSCode itself). VSCode does not need to be quit — logs are append-only and the current session's directory is the most recently modified one.
tools: Bash,Read,Grep,Glob
---

# VSCode logs (`logs/<sessionId>/*.log`)

The diagnostic stream. Plain-text, line-per-event, append-only.

## Why

VSCode creates a new `logs/<ISO-timestamp>/` directory on every launch. Inside each, fixed filenames map to subsystems:

| File | Subsystem | What to look for |
| ---- | --------- | ---------------- |
| `main.log` | Electron main process | Window creation, IPC, startup failures, settings sync auth |
| `renderer1.log` (and `2`, `3`…) | One per VSCode window | UI crashes, theme errors, webview load failures |
| `sharedprocess.log` | Shared process (settings sync, extension management) | Marketplace requests, sync conflicts |
| `ptyhost.log` | Pseudo-terminal host (integrated terminal) | Shell spawn failures, terminal renderer errors |
| `exthost.log` (per window: `exthost1.log`, `exthost2.log`) | Extension host | Extension activation, crashes inside extensions, `console.log` from extensions |
| `network.log` | (when enabled) | Outbound HTTP including proxy failures |
| `telemetry.log` | (when enabled) | What was reported to Microsoft |

Each line is prefixed with an ISO timestamp + level (`[error]`, `[warning]`, `[info]`, `[trace]`).

## Location

```bash
BASE="$HOME/Library/Application Support/Code"
LOGS="$BASE/logs"
LATEST=$(ls -td "$LOGS"/*/ 2>/dev/null | head -1)
```

## Quit VSCode first?

**No.** Logs are append-only. Reading them while VSCode runs is safe. Pruning *non-current* sessions is also safe.

## Inspect

```bash
# 1. Latest session directory:
LATEST=$(ls -td "$LOGS"/*/ | head -1)
echo "Latest session: $LATEST"
ls -la "$LATEST"

# 2. Tail the live extension host log (most useful single command):
tail -F "$LATEST/exthost1.log"

# 3. Errors across the latest session:
grep -nH '\[error\]' "$LATEST"/*.log | head -50

# 4. Errors across ALL sessions in the last 7 days:
find "$LOGS" -type f -name '*.log' -mtime -7 -exec grep -lH '\[error\]' {} +

# 5. Extension activation failures (most common debug target):
grep -nE 'Activating extension|Activation failed|Could not load extension' "$LATEST"/exthost*.log

# 6. Startup time breakdown (main.log emits per-stage timing):
grep -E 'startup|window restored|workbench loaded' "$LATEST/main.log"

# 7. Filter by one extension ID:
ext="ms-python.python"
grep -nH "$ext" "$LATEST"/exthost*.log | head
```

Pretty-print one log line (helpful when fields are dense):

```bash
head -1 "$LATEST/main.log"
# [2026-05-14 09:12:33.420] [main] [info] update#setState idle
```

## Edit

**No edit path.** Logs are diagnostic records; edits invalidate any later forensic analysis.

## Backup

Rarely useful. If a specific session captured a hard-to-reproduce bug, archive it:

```bash
tar -czf "$HOME/Desktop/vscode-logs-$(basename "$LATEST").tgz" -C "$LOGS" "$(basename "$LATEST")"
```

## Clean / Prune

VSCode never deletes old log dirs on its own. They accumulate ~1 per launch, ~1–5 MB each.

```bash
# Inspect total usage:
du -sh "$LOGS"
ls -td "$LOGS"/*/ | wc -l

# Dry run — what would be pruned (older than 14 days):
find "$LOGS" -mindepth 1 -maxdepth 1 -type d -mtime +14 -print

# Apply:
find "$LOGS" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +

# More aggressive — keep only the 10 most recent sessions:
ls -td "$LOGS"/*/ | tail -n +11 | xargs -I{} rm -rf "{}"

# Never delete the currently-active session:
RUNNING_PID=$(pgrep -x Code | head -1)
[[ -n "$RUNNING_PID" ]] && {
  # Skip whichever dir was modified in the last 60s
  find "$LOGS" -mindepth 1 -maxdepth 1 -type d -mmin +1 -mtime +14 -exec rm -rf {} +
}
```

## Hard rules

- **Never delete the currently-active session directory** while VSCode is running. If you do, VSCode keeps writing to the (now-orphaned) file handle and you lose nothing immediately, but the next log rotation can fail.
- **Never grep `*.log` recursively from `$BASE`** — you will also walk into `Cache/`, `CachedData/`, and `User/History/`, all of which can produce GB of noise. Scope to `$LOGS`.
- **Logs may contain identifying paths, branch names, and extension state.** Treat them as semi-private before sharing in an issue tracker.
- **Don't enable `network.log`/`trace`-level for routine use.** They explode log sizes by 10–100× and can capture tokens in URLs.

## Examples

### 1. Find why an extension failed to activate

```bash
LATEST=$(ls -td "$HOME/Library/Application Support/Code/logs"/*/ | head -1)
ext="dbaeumer.vscode-eslint"
grep -nE "($ext|Activation failed|Could not load)" "$LATEST"/exthost*.log
```

### 2. Recent renderer crashes

```bash
LATEST=$(ls -td "$HOME/Library/Application Support/Code/logs"/*/ | head -1)
grep -nE '(renderer.*crash|Render frame|Out of memory)' "$LATEST"/renderer*.log "$LATEST/main.log"
```

### 3. Prune logs older than 30 days

```bash
LOGS="$HOME/Library/Application Support/Code/logs"
du -sh "$LOGS"
find "$LOGS" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +
du -sh "$LOGS"
```
