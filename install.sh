#!/usr/bin/env bash
# install.sh — fetch and install symlink-agents
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash
#   wget -qO-  https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash
#
# With flags (note the `-s --` so bash passes args to the script, not to itself):
#   curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash -s -- --run
#   curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash -s -- --prefix=/usr/local/bin
#   curl -fsSL https://raw.githubusercontent.com/carlosmarte/agent-vscode-copilot-custom-agents/main/install.sh | bash -s -- --ref=v0.1.0
#
# Env overrides (alternative to flags):
#   AGENTS_REF=main           git ref (branch/tag/sha) to fetch from
#   AGENTS_PREFIX=~/.local/bin  install directory
#   AGENTS_RUN=1              run symlink-agents after install (interactive)

set -euo pipefail

REPO_OWNER="carlosmarte"
REPO_NAME="agent-vscode-copilot-custom-agents"
SCRIPT_NAME="symlink-agents"
SCRIPT_PATH_IN_REPO=".bin/${SCRIPT_NAME}"

REF="${AGENTS_REF:-main}"
PREFIX="${AGENTS_PREFIX:-$HOME/.local/bin}"
RUN_AFTER="${AGENTS_RUN:-0}"

# ---- arg parsing -------------------------------------------------------------

usage() {
  cat <<EOF
install.sh — fetch and install ${SCRIPT_NAME}

Flags:
  --ref=<git-ref>      branch / tag / sha to fetch from (default: ${REF})
  --prefix=<dir>       install directory (default: ${PREFIX})
  --run                run ${SCRIPT_NAME} after install (from /dev/tty so the menu works)
  -h, --help           show this help

Equivalent env vars: AGENTS_REF, AGENTS_PREFIX, AGENTS_RUN=1
EOF
}

for arg in "$@"; do
  case "$arg" in
    --ref=*)    REF="${arg#--ref=}" ;;
    --prefix=*) PREFIX="${arg#--prefix=}" ;;
    --run)      RUN_AFTER=1 ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "unknown flag: $arg" 1>&2; usage 1>&2; exit 2 ;;
  esac
done

# ---- helpers -----------------------------------------------------------------

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_red=$'\033[31m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_blue=$'\033[34m'

ok()   { printf "%s✓%s %s\n" "$c_green" "$c_reset" "$*"; }
info() { printf "%s•%s %s\n" "$c_blue"  "$c_reset" "$*"; }
warn() { printf "%s!%s %s\n" "$c_yellow" "$c_reset" "$*"; }
die()  { printf "%s✗%s %s\n" "$c_red"   "$c_reset" "$*" 1>&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

fetch_to() {
  # fetch_to <url> <dest>
  local url="$1" dest="$2"
  if have curl; then
    curl -fsSL --proto '=https' --tlsv1.2 -o "$dest" "$url" || return 1
  elif have wget; then
    wget -q -O "$dest" "$url" || return 1
  else
    die "neither curl nor wget is available — cannot download $url"
  fi
}

# ---- install -----------------------------------------------------------------

URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REF}/${SCRIPT_PATH_IN_REPO}"
DEST="${PREFIX%/}/${SCRIPT_NAME}"

printf "%s%s%s\n" "$c_bold" "Installing ${SCRIPT_NAME}" "$c_reset"
info "source : $URL"
info "target : $DEST"

mkdir -p "$PREFIX" || die "could not create $PREFIX"

tmp="$(mktemp -t "${SCRIPT_NAME}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

if ! fetch_to "$URL" "$tmp"; then
  die "download failed: $URL"
fi

# Cheap sanity check — must be a bash script
if ! head -n 1 "$tmp" | grep -qE '^#!.*(ba)?sh'; then
  die "downloaded file does not look like a shell script (got: $(head -n1 "$tmp"))"
fi

install -m 0755 "$tmp" "$DEST" 2>/dev/null || {
  # Fallback if `install` isn't available or PREFIX needs perms we don't have.
  cp "$tmp" "$DEST" && chmod 0755 "$DEST"
}

ok "installed ${SCRIPT_NAME} → $DEST"

# ---- PATH advisory -----------------------------------------------------------

case ":${PATH}:" in
  *":${PREFIX}:"*) ok "$PREFIX is on your PATH" ;;
  *)
    warn "$PREFIX is not on your PATH"
    printf "    add it with one of:\n"
    printf "      ${c_dim}# bash${c_reset}\n      echo 'export PATH=\"%s:\$PATH\"' >> ~/.bashrc\n" "$PREFIX"
    printf "      ${c_dim}# zsh${c_reset}\n      echo 'export PATH=\"%s:\$PATH\"' >> ~/.zshrc\n" "$PREFIX"
    ;;
esac

# ---- next steps --------------------------------------------------------------

cat <<EOF

${c_bold}Next steps${c_reset}
  Run the picker:        $DEST
  Run all steps:         $DEST --all
  Show current state:    $DEST --status
  Help:                  $DEST --help
EOF

# ---- optional immediate run --------------------------------------------------

if [[ "$RUN_AFTER" == "1" ]]; then
  echo
  info "running ${SCRIPT_NAME} (interactive — reading from /dev/tty)"
  # When this installer was piped via `curl | bash`, stdin is the pipe — not the
  # user's terminal — so the picker's `read` would receive EOF immediately.
  # Re-attach stdin to the controlling terminal before execing.
  if [[ -r /dev/tty ]]; then
    exec "$DEST" </dev/tty
  else
    warn "/dev/tty not readable — running non-interactively with --status"
    exec "$DEST" --status
  fi
fi
