---
name: vscode-jsonc-config
description: Inspect, edit, and back up the JSONC (JSON with Comments) config files that own VSCode's global behavior — `User/settings.json`, `User/keybindings.json`, and the top-level `argv.json`. Use when adding/removing a setting, auditing a sluggish/misbehaving editor, comparing settings between machines, or recovering from a corrupted config. Preserves `//` and `/* */` comments on edit. Does NOT touch SQLite state, snippets, or workspace-scoped settings (those live in `.vscode/settings.json` inside each project). VSCode does not need to be quit — these files are read fresh each launch.
tools: Bash,Read,Write,Edit,Grep,Glob
---

# VSCode JSONC config (`settings.json`, `keybindings.json`, `argv.json`)

The three top-of-stack files that define VSCode's global behavior. JSONC = JSON with Comments — `//` line comments and `/* */` block comments are legal.

## Why

`settings.json` is the user-global setting overlay (workspace `.vscode/settings.json` wins for an open folder). `keybindings.json` holds user-defined chords on top of the default keymap. `argv.json` configures Electron/Chromium launch flags (e.g. `disable-hardware-acceleration`, `enable-crash-reporter`). All three are JSONC, so a naive `jq .` will refuse to parse them — comments must be stripped first, but never written back stripped.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"
# Insiders:  BASE="$HOME/Library/Application Support/Code - Insiders"

SETTINGS="$BASE/User/settings.json"
KEYBINDS="$BASE/User/keybindings.json"
ARGV="$BASE/User/argv.json"

# Profile variants (each profile has its own copy):
# "$BASE/User/profiles/<profile-id>/settings.json"
# "$BASE/User/profiles/<profile-id>/keybindings.json"
```

## Quit VSCode first?

**No.** VSCode rereads these on launch and on most setting writes from the UI; manual edits land on next launch (or via Command Palette → "Developer: Reload Window").

## Inspect

JSONC ≠ JSON. Strip comments **only for reading**:

```bash
strip_jsonc() {
  sed -E '
    /^[[:space:]]*\/\//d        # drop // line comments
    /\/\*/,/\*\// {              # drop /* block */ comments
      /\/\*/!{/\*\//!d}
      s:/\*.*\*/::g
      s:/\*.*$::
      s:^.*\*/::
    }
    /^[[:space:]]*$/d            # drop blank lines
  ' "$1"
}

# List every setting key:
strip_jsonc "$SETTINGS" | jq -r 'keys[]'

# Read a single value:
strip_jsonc "$SETTINGS" | jq '."editor.fontSize"'

# Count user-defined keybindings:
strip_jsonc "$KEYBINDS" | jq 'length'

# Dump argv.json flags:
strip_jsonc "$ARGV" | jq .
```

For richer JSONC parsing, `npx jsonc-parser` or the `dasel -p jsonc` CLI both work without stripping.

## Edit

**Preserve comments.** Use the `Edit` tool with the exact surrounding text, or use the VSCode UI (Command Palette → "Preferences: Open User Settings (JSON)") which round-trips comments cleanly.

Mechanical edit recipe:

1. Back up first (see next section).
2. Locate the line with `grep -n '"editor.fontSize"' "$SETTINGS"`.
3. Edit in place — change the value only, never re-serialize the whole file.
4. Validate with `strip_jsonc "$SETTINGS" | jq . >/dev/null && echo OK`.

For programmatic key adds, the safer path is:

```bash
# Use VSCode CLI when you can — it preserves JSONC structure:
code --list-extensions                  # read
code --install-extension ms-python.python   # adds to extensions.json, not settings.json
```

There is no first-class CLI to set `settings.json` keys. Hand-edit or use the UI.

## Backup

Always before any write:

```bash
cp "$SETTINGS" "$SETTINGS.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp "$KEYBINDS" "$KEYBINDS.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp "$ARGV"     "$ARGV.bak.$(date -u +%Y%m%dT%H%M%SZ)"
```

Backups sit next to the original. They are not scanned by VSCode (only the canonical filename is loaded).

## Clean / Prune

**Do not clean.** These three files are user-authored and tiny (KB, not MB). The only "clean" worth doing is removing stale `*.bak.*` files you created above:

```bash
find "$BASE/User" -maxdepth 1 -name '*.bak.*' -mtime +30 -print
```

## Hard rules

- **Never write back the comment-stripped form.** `strip_jsonc` is read-only — piping `jq` output back over the original destroys every `//` comment and breaks the file's documentation.
- **Never commit `settings.json` into the source repo you happen to have open.** It is machine-global and often contains paths, license keys, or extension auth tokens.
- **Trailing commas are legal in JSONC** but illegal in plain JSON. If you must `jq` the result, the comma-stripping is handled by `jsonc-parser`/`dasel`; bare `jq` will reject `{ "a": 1, }`.
- **The `argv.json` file affects every VSCode launch.** A bad flag bricks startup. Always back up before editing and know the recovery path: `rm "$ARGV"` regenerates a default.

## Examples

### 1. Audit which extensions a user has pinned

```bash
strip_jsonc "$SETTINGS" | jq -r '. | to_entries[] | select(.key | startswith("extensions.")) | "\(.key) = \(.value)"'
```

### 2. Add a setting safely

```bash
cp "$SETTINGS" "$SETTINGS.bak.$(date -u +%Y%m%dT%H%M%SZ)"
# Then either:
code "$SETTINGS"                                   # interactive
# or surgically with Edit tool (matches the line preserving // comments above it)
```

### 3. Recover from a corrupt `argv.json`

```bash
cp "$ARGV" "$ARGV.broken.$(date -u +%Y%m%dT%H%M%SZ)"
rm "$ARGV"
open -a "Visual Studio Code"   # regenerates a default argv.json
```
