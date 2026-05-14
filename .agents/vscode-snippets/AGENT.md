---
name: vscode-snippets
description: Inspect, edit, validate, and prune VSCode user snippets under `User/snippets/`. Handles both per-language `<lang>.json` (single-language) and `*.code-snippets` (multi-language with `scope` field) files, both of which are JSONC. Use when adding a snippet, auditing for unused or duplicate `prefix` collisions, validating snippet schema before committing to a snippets repo, or migrating snippets between machines. Does NOT touch extension-shipped snippets (those live inside extension packages under `extensions/`). VSCode picks up changes within ~1 second of save — no quit required.
tools: Bash,Read,Write,Edit,Grep,Glob
---

# VSCode user snippets (`User/snippets/*.{json,code-snippets}`)

User-authored snippet libraries that drive tab-completion templates.

## Why

Two filename conventions, same schema:

- `User/snippets/<lang>.json` — single-language, the `scope` field is implicit from the filename (e.g. `python.json` is Python-only).
- `User/snippets/<name>.code-snippets` — multi-language, the `scope` field is a comma-separated list of language IDs (e.g. `"javascript,typescript"`).

Both are JSONC. Each snippet is a top-level key (the *name*, shown in IntelliSense) whose value is `{prefix, body, description, scope?}`. `prefix` is what you type; `body` is a string or string array with `$1`, `$2`, `${1:default}` placeholders.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"
SNIPDIR="$BASE/User/snippets"

# Profile variants:
# "$BASE/User/profiles/<profile-id>/snippets/"
```

## Quit VSCode first?

**No.** Snippet files are watched. Saves are picked up live by IntelliSense.

## Inspect

```bash
# List every snippet file:
ls -la "$SNIPDIR"

# Dump every snippet name across all files (JSONC-safe):
strip_jsonc() { sed -E '/^[[:space:]]*\/\//d; /\/\*/,/\*\//{/\/\*/!{/\*\//!d}; s:/\*.*\*/::g; s:/\*.*$::; s:^.*\*/::}; /^[[:space:]]*$/d' "$1"; }
for f in "$SNIPDIR"/*.{json,code-snippets}; do
  [[ -f "$f" ]] || continue
  echo "=== $(basename "$f") ==="
  strip_jsonc "$f" | jq -r 'keys[]'
done

# Find every prefix (collisions across files are a common bug):
for f in "$SNIPDIR"/*.{json,code-snippets}; do
  [[ -f "$f" ]] || continue
  strip_jsonc "$f" | jq -r --arg file "$(basename "$f")" 'to_entries[] | "\($file)\t\(.value.prefix)\t\(.key)"'
done | sort -k2

# Show one snippet's body:
strip_jsonc "$SNIPDIR/javascript.json" | jq '."Console log"'
```

## Edit

Validate the per-snippet schema after every change:

```bash
validate_snippets() {
  strip_jsonc "$1" | jq -e '
    to_entries | all(
      (.value | type == "object")
      and (.value.prefix | type | IN("string","array"))
      and (.value.body   | type | IN("string","array"))
    )
  ' >/dev/null && echo "OK $1" || echo "INVALID $1"
}
for f in "$SNIPDIR"/*.{json,code-snippets}; do [[ -f "$f" ]] && validate_snippets "$f"; done
```

Add a new snippet — use the `Edit` tool to insert before the closing `}`:

```jsonc
"Print to stderr": {
  "prefix": "perr",
  "body": "console.error($1);",
  "description": "console.error with cursor"
}
```

Comma discipline: every snippet entry except the last needs a trailing `,`. JSONC tolerates a trailing comma after the *last* entry, but other parsers may not — prefer no trailing comma.

## Backup

```bash
cp -R "$SNIPDIR" "$SNIPDIR.bak.$(date -u +%Y%m%dT%H%M%SZ)"
```

The directory is small (KB range), so a full-tree backup is cheap and atomic.

## Clean / Prune

Three useful prune workflows:

```bash
# 1. Find snippet files with no entries (empty {}):
for f in "$SNIPDIR"/*.{json,code-snippets}; do
  [[ -f "$f" ]] || continue
  n=$(strip_jsonc "$f" | jq 'length')
  (( n == 0 )) && echo "EMPTY $f"
done

# 2. Find duplicate prefixes within one file (real collisions):
for f in "$SNIPDIR"/*.{json,code-snippets}; do
  [[ -f "$f" ]] || continue
  dups=$(strip_jsonc "$f" | jq -r '[.[].prefix] | group_by(.) | map(select(length>1)) | flatten | unique[]')
  [[ -n "$dups" ]] && { echo "DUPLICATES in $f:"; echo "$dups"; }
done

# 3. Find prefixes never likely to be typed (length > 12):
for f in "$SNIPDIR"/*.{json,code-snippets}; do
  [[ -f "$f" ]] || continue
  strip_jsonc "$f" | jq -r --arg file "$(basename "$f")" 'to_entries[] | select((.value.prefix | tostring | length) > 12) | "\($file)\t\(.value.prefix)"'
done
```

## Hard rules

- **Each snippet name (top-level key) must be unique within its file.** JSONC parsers silently keep the last duplicate; you will lose snippets.
- **`scope` is mandatory in `*.code-snippets`** (the multi-language form). Without it, the snippet appears in every file type — usually not what you want.
- **Body indentation is preserved as written.** Use `\t` for tabs in the JSON string, not literal tab characters (they encode unreliably).
- **Do not commit snippets containing secrets or per-user paths.** A snippet that types out an API key is a credential leak waiting to happen.

## Examples

### 1. Migrate a snippet to a different language file

```bash
cp "$SNIPDIR/javascript.json" "$SNIPDIR/javascript.json.bak.$(date -u +%Y%m%dT%H%M%SZ)"
# Extract one snippet and copy it into typescript.json with Edit tool
strip_jsonc "$SNIPDIR/javascript.json" | jq '."Console log"'
```

### 2. Audit before committing snippets to a dotfiles repo

```bash
# Round-trip through jq to catch syntax errors:
for f in "$SNIPDIR"/*.{json,code-snippets}; do
  [[ -f "$f" ]] || continue
  strip_jsonc "$f" | jq empty 2>&1 | head -3
done
```

### 3. Find which file owns the `clog` prefix

```bash
for f in "$SNIPDIR"/*.{json,code-snippets}; do
  [[ -f "$f" ]] || continue
  strip_jsonc "$f" | jq -e 'to_entries[] | select(.value.prefix == "clog")' >/dev/null \
    && echo "$f owns clog"
done
```
