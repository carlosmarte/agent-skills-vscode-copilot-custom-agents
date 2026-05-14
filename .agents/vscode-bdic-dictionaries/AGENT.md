---
name: vscode-bdic-dictionaries
description: Enumerate, identify, and remove the Chromium binary spell-check dictionaries (`.bdic`) under `Dictionaries/`. Each file is ~5 MB of compressed Hunspell-derived data for one locale (e.g. `en-US-10-1.bdic`). Use when reclaiming disk space on a multi-locale system, auditing which languages VSCode currently believes you spell-check in, or replacing a corrupted dictionary. **Do NOT hand-edit `.bdic` files** — they are binary with embedded checksums. VSCode redownloads missing dictionaries on demand when the locale is needed (Chromium's auto-download mechanism), so deletion is reversible.
tools: Bash,Read,Grep,Glob
---

# VSCode dictionaries (`Dictionaries/*.bdic`)

Chromium-format binary spell-check dictionaries. One per locale.

## Why

`.bdic` is Chromium's compiled, compressed binary dictionary format (derived from Hunspell `.dic`/`.aff` source pairs). Each file is self-contained and named with the BCP-47 locale plus version suffix:

```
en-US-10-1.bdic    en-GB-10-1.bdic    es-ES-3-0.bdic    de-DE-3-0.bdic
```

The two trailing numeric segments are the dictionary `major-minor` version (refreshed via Chromium updates, not VSCode releases). Typical sizes: 2–6 MB per locale; a system that picked up 8 locales has accumulated ~30–50 MB of dictionaries you may not use.

Which dictionary VSCode uses for a given document depends on:
- Built-in spell check: VSCode core does not ship spell-check; this folder is populated by webviews and by extensions like `streetsidesoftware.code-spell-checker` or `ban.spellright` that proxy to the platform.
- macOS system locale (queried at startup) determines which dictionary the OS prefers when an extension delegates to the system speller.

## Location

```bash
BASE="$HOME/Library/Application Support/Code"
DICT="$BASE/Dictionaries"
```

## Quit VSCode first?

**No.** The dictionary files are read-only memory-mapped; you can delete them while VSCode runs. The currently-mapped pages stay alive until quit, but disk space frees on quit even without an explicit unmap.

## Inspect

```bash
# 1. List installed locales:
ls -la "$DICT"

# 2. Sizes per locale:
for f in "$DICT"/*.bdic; do
  printf '%s\t%s\n' "$(du -h "$f" | cut -f1)" "$(basename "$f")"
done | sort -h

# 3. Total disk usage:
du -sh "$DICT"

# 4. Verify file format (BDIC files start with `BDic` magic):
for f in "$DICT"/*.bdic; do
  head -c 4 "$f" | xxd -p | head -c 8
  echo "  $(basename "$f")"
done
# Each line should print: 42446963   (the bytes "BDic")

# 5. Identify the BCP-47 locale code(s) you actually want:
defaults read -g AppleLocale 2>/dev/null         # macOS system locale
defaults read -g AppleLanguages 2>/dev/null      # user language order
```

## Edit

**No edit path.** `.bdic` files are compiled binary; hand-editing breaks the checksum and Chromium rejects the file. If you need a custom dictionary, install a spell-check extension that loads `.dic`/`.aff` from a user path instead.

To **replace** one (e.g. upstream pushed a corrupt version):

```bash
# Move the suspect file out of the way; on next use, Chromium re-fetches:
mv "$DICT/en-US-10-1.bdic" "$DICT/en-US-10-1.bdic.bad.$(date -u +%Y%m%dT%H%M%SZ)"
# Trigger a webview that uses spell-check; Chromium pulls a fresh copy.
```

## Backup

Optional and cheap:

```bash
cp -R "$DICT" "$DICT.bak.$(date -u +%Y%m%dT%H%M%SZ)"
```

But since Chromium re-downloads on demand, the more pragmatic recovery is "just delete and let it refetch."

## Clean / Prune

```bash
# Inspect:
du -sh "$DICT"
ls "$DICT" | wc -l

# Dry run — identify locales you don't want (everything except en-* and your system locale):
KEEP_LOCALES=("en-US" "en-GB")
for f in "$DICT"/*.bdic; do
  base=$(basename "$f" .bdic)
  locale="${base%-*-*}"                            # strip trailing -N-N version
  keep=0
  for k in "${KEEP_LOCALES[@]}"; do [[ "$locale" == "$k" ]] && keep=1 && break; done
  (( keep == 0 )) && echo "WOULD DELETE $f  (locale $locale)"
done

# Apply (after review):
KEEP_LOCALES=("en-US" "en-GB")
for f in "$DICT"/*.bdic; do
  base=$(basename "$f" .bdic)
  locale="${base%-*-*}"
  keep=0
  for k in "${KEEP_LOCALES[@]}"; do [[ "$locale" == "$k" ]] && keep=1 && break; done
  (( keep == 0 )) && rm -f "$f"
done

du -sh "$DICT"
```

### Nuclear option

Delete every dictionary and let VSCode/Chromium repopulate exactly what's needed:

```bash
rm -f "$DICT"/*.bdic
# Restart VSCode. Spell-check works in en-US (default) immediately;
# other locales repopulate on first use.
```

## Hard rules

- **Never hand-edit a `.bdic` file.** Embedded checksum + compressed tables — manual edits produce silent corruption.
- **Don't add `.dic`/`.aff` files here.** This directory is for compiled binary `.bdic` only; raw Hunspell files belong with the extension that loads them.
- **Don't delete this folder entirely.** Chromium expects `Dictionaries/` to exist; removing it can cause spell-check init failures. Empty it, don't delete it.
- **Don't commit `.bdic` to any source repo.** They're per-machine, large, and downloaded automatically — checking them in is pure churn.

## Examples

### 1. See what locales are installed and how much space they take

```bash
DICT="$HOME/Library/Application Support/Code/Dictionaries"
for f in "$DICT"/*.bdic; do
  printf '%s\t%s\n' "$(du -h "$f" | cut -f1)" "$(basename "$f")"
done | sort -h
du -sh "$DICT"
```

### 2. Strip everything except English

```bash
DICT="$HOME/Library/Application Support/Code/Dictionaries"
for f in "$DICT"/*.bdic; do
  base=$(basename "$f")
  case "$base" in
    en-*) ;;          # keep
    *) rm -f "$f" ;;
  esac
done
```

### 3. Force-refresh a suspect dictionary

```bash
DICT="$HOME/Library/Application Support/Code/Dictionaries"
mv "$DICT/en-US-10-1.bdic" "/tmp/en-US-bad.bdic.$(date -u +%Y%m%dT%H%M%SZ)"
# Restart VSCode + open a webview with text; Chromium re-fetches the locale.
```
