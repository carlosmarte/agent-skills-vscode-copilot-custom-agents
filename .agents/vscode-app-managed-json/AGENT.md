---
name: vscode-app-managed-json
description: Read-only reference for the small JSON files that VSCode generates and owns by itself — `Machine/` (per-host UUID used by Settings Sync), `rapid_render.json` (cached theme colors for splash-screen pre-paint), and the various lockfiles VSCode drops at the Code root. Use when curiosity, debugging Settings Sync identity drift, or auditing what VSCode persists outside `User/`. **Never edit these files.** They are app-managed, contain no user authoring, and editing them either silently regenerates the file (best case) or breaks Settings Sync identity / splash rendering (worst case). Deletion is mostly safe — VSCode regenerates them on next launch.
tools: Bash,Read,Grep,Glob
---

# VSCode app-managed JSON (`Machine/`, `rapid_render.json`, lockfiles)

The bookkeeping layer. Files VSCode writes for itself, never for you.

## Why

These files live at the top of the Code folder (or in single-purpose subdirs) and serve internal VSCode needs:

| File / Dir | What it does | Editing? | Deletion impact |
| ---------- | ------------ | -------- | --------------- |
| `Machine/` | Stable UUID identifying this Mac to Settings Sync. JSON `{"machineId":"...","macMachineId":"..."}` | **Never edit** | Settings Sync treats this host as new → may re-pull settings on next launch |
| `rapid_render.json` | Theme background/foreground colors cached for splash-screen pre-paint (window appears with correct theme before extension host loads) | **Never edit** | Splash briefly flashes default colors on next launch; regenerates immediately |
| `Crashpad/` | Chromium crash-report database (not JSON; metadata is) | **Never edit** | Loses any pending crash reports queued for upload |
| `SingletonLock`, `SingletonCookie`, `SingletonSocket` | Single-instance lock files (created at launch, removed at quit) | **Never edit** | If stale (VSCode crashed), delete to allow new launch |
| `Network Persistent State` | JSON of HTTP/2 + QUIC session resumption hints | **Never edit** | Connections slightly slower until Chromium re-learns servers |
| `Trust Tokens` (SQLite, not JSON, but app-managed) | Privacy Pass tokens for some web requests | **Never edit** | Usually empty in VSCode; no functional impact |

The User-data layer (`User/settings.json`, snippets, keybindings) is yours. The cache layer (`Cache/`, `CachedData/`) is regenerable. **This layer is identity and bookkeeping** — leave it alone unless a specific lock is preventing VSCode from launching.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"

MACHINE="$BASE/Machine"
RAPID="$BASE/rapid_render.json"
CRASHPAD="$BASE/Crashpad"
SINGLETONS=("$BASE/SingletonLock" "$BASE/SingletonCookie" "$BASE/SingletonSocket")
NET_STATE="$BASE/Network Persistent State"
```

## Quit VSCode first?

For **inspection: no**. For **deletion of singleton lockfiles: yes** (you only delete them when VSCode is already quit/crashed and can't relaunch).

## Inspect

```bash
# 1. Machine identity (used by Settings Sync to identify this host):
cat "$MACHINE"/* 2>/dev/null | jq .
# Expect: { "machineId": "<uuid>", "macMachineId": "<uuid>" }

# 2. Rapid render cache:
cat "$RAPID" | jq .
# Expect: { "windowBorder":"...", "themeBackground":"#1e1e1e", "themeForeground":"#cccccc" }

# 3. Singleton lockfiles (present only while VSCode is running, or stale after a crash):
for f in "${SINGLETONS[@]}"; do
  [[ -e "$f" ]] && printf '%s\t%s\n' "PRESENT" "$f" || printf '%s\t%s\n' "absent " "$f"
done

# 4. Crashpad pending reports (informational):
ls -la "$CRASHPAD/pending" 2>/dev/null | head

# 5. Network persistent state:
[[ -f "$NET_STATE" ]] && jq 'keys' "$NET_STATE"

# 6. Confirm a singleton lockfile is stale (no Code process owns it):
[[ -e "$BASE/SingletonLock" ]] && {
  pgrep -x Code >/dev/null && echo "VSCode running — lockfile is legitimate" \
                            || echo "VSCode not running — lockfile is stale, safe to delete"
}
```

## Edit

**Do not edit any file in this category.** All of them are written by VSCode/Chromium with internal invariants:

- `Machine/<file>` — UUID format checked at startup; a malformed value disables Settings Sync silently.
- `rapid_render.json` — overwritten on every theme change anyway; editing is futile.
- `Network Persistent State` — Chromium-internal protobuf-shaped JSON; bad shape → file ignored → no functional damage but no benefit either.

If you have an itch to change something, it almost certainly belongs in `User/settings.json` — see the `vscode-jsonc-config` agent.

## Backup

Backup is rarely useful, but the `Machine/` directory is worth preserving once (so a future "why does Settings Sync see two of me" mystery has an answer):

```bash
cp -R "$MACHINE" "$MACHINE.bak.$(date -u +%Y%m%dT%H%M%SZ)"
```

`rapid_render.json` and singletons regenerate; no backup point.

## Clean / Prune

```bash
# Stale singleton lockfiles (only when VSCode is not running):
pgrep -x Code >/dev/null && { echo "VSCode is running — do not delete singletons"; exit 1; }

for f in "$BASE/SingletonLock" "$BASE/SingletonCookie" "$BASE/SingletonSocket"; do
  [[ -e "$f" ]] && { echo "removing stale $f"; rm -f "$f"; }
done

# rapid_render.json — harmless to delete (regenerates on first window paint):
rm -f "$RAPID"

# Crashpad/ — only if you know you don't want pending crash uploads:
# rm -rf "$CRASHPAD/pending"
```

**Never** `rm -rf "$MACHINE"`. The next launch will generate new IDs and Settings Sync will treat your Mac as a different host.

## Hard rules

- **`Machine/` is identity. Treat as read-only.** Even backing it up is fine; editing it isn't.
- **Singletons mean "VSCode is running here right now."** Delete them only when you've confirmed no `Code` process is alive.
- **`rapid_render.json` is not a settings file.** It is regenerated by the theme system; user-side settings live in `User/settings.json`.
- **`Crashpad/`'s pending reports may contain stack traces with file paths.** Treat as semi-private when sharing.
- **These files are per-machine.** None should ever be committed to a source repo — see the `User/` exclusions in your global `.gitignore`.

## Examples

### 1. Audit machine identity (e.g. before reinstalling macOS)

```bash
MACHINE="$HOME/Library/Application Support/Code/Machine"
cat "$MACHINE"/* | jq .
# Record the IDs somewhere — if you need to keep Settings Sync continuity across a reinstall,
# Microsoft's flow is to re-authenticate, not to preserve these IDs.
```

### 2. Unstick VSCode that won't launch after a crash

```bash
BASE="$HOME/Library/Application Support/Code"
pgrep -x Code >/dev/null && { echo "VSCode is running — fix that first"; exit 1; }
rm -f "$BASE/SingletonLock" "$BASE/SingletonCookie" "$BASE/SingletonSocket"
open -a "Visual Studio Code"
```

### 3. Confirm rapid_render.json matches your current theme

```bash
RAPID="$HOME/Library/Application Support/Code/rapid_render.json"
jq '.themeBackground, .themeForeground' "$RAPID"
# Compare visually to your VSCode's current theme — should match the last theme you used.
# If it doesn't, just delete the file; next launch refreshes it.
```
