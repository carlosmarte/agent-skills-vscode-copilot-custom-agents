# GitHub Copilot CLI — Command-Line Argument Reference

This document lists every **flag and argument passed to the `copilot` binary at invocation time** — not slash commands typed inside an interactive session.

> Source: [GitHub Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference).
> Run `copilot --help` for the live, version-accurate list.

---

## 🚀 Core Execution

Flags that decide what Copilot does when it starts.

| Flag | Purpose | Values |
| --- | --- | --- |
| `-p, --prompt <PROMPT>` | Execute a prompt programmatically and exit. | Any string |
| `-i, --interactive <PROMPT>` | Start an interactive session pre-seeded with the prompt. | Any string |
| `--mode <MODE>` | Set the initial agent mode. | `interactive`, `plan`, `autopilot` |
| `--plan` | Shorthand for `--mode plan`. | — |
| `--autopilot` | Enable autonomous continuation across steps. | — |
| `--max-autopilot-continues <N>` | Cap the number of autopilot continuation messages. | Integer |

```bash
# Programmatic one-shot
copilot -p "Show this week's commits and summarize them"

# Interactive with seed prompt
copilot -i "Help me refactor the auth module"

# Plan first, then approve
copilot --plan -p "Migrate the cart page to Stripe Checkout"

# Bounded autopilot
copilot --autopilot --max-autopilot-continues 5 -p "Bring orders/ to 80% coverage"
```

---

## 🔁 Session Management

Resume prior work or wire up remote control.

| Flag | Purpose | Values |
| --- | --- | --- |
| `--resume [VALUE]` | Resume a previous session by ID, name, or prefix. With no value, prompts a picker. | Session ID / name / prefix |
| `--continue` | Resume the most recent session. | — |
| `--connect [SESSION-ID]` | Connect directly to a remote session or task. | Session/task ID |
| `-n, --name <NAME>` | Name the new session for easier resume later. | Any string |
| `--remote` / `--no-remote` | Enable / disable remote access for this session. | — |

```bash
copilot --continue
copilot --resume feature-stripe-checkout
copilot -n "orders-coverage" -p "Add tests for orders/service.ts"
copilot --remote -p "Long-running migration; I want to steer from mobile"
```

---

## 🔐 Permissions & Access Control

Control what tools and paths Copilot can use without prompting. **Deny rules take precedence over allow rules.**

| Flag | Purpose | Values |
| --- | --- | --- |
| `--allow-all` | Grant all permissions. | — |
| `--yolo` | Alias for `--allow-all`. | — |
| `--allow-all-tools` | Auto-approve every tool. | — |
| `--allow-all-paths` | Disable file-path restrictions. | — |
| `--allow-all-urls` | Allow all URLs without prompting. | — |
| `--allow-tool <TOOL>` | Permit specific tools. | `shell(cmd)`, `write`, `MCP_SERVER_NAME` (comma-sep) |
| `--allow-url <URL>` | Allow specific URLs / domains. | Domain or URL patterns |
| `--deny-tool <TOOL>` | Prohibit specific tools. Wins over allow. | Tool names or patterns |
| `--deny-url <URL>` | Block specific URLs / domains. | Domain or URL patterns |
| `--available-tools <TOOL>` | Restrict the tool set the agent can call. | Comma-separated names |
| `--excluded-tools <TOOL>` | Hide tools from the model entirely. | Comma-separated names |
| `--no-ask-user` | Never prompt the user for permission. | — |
| `--add-dir <PATH>` | Grant file access to a directory (repeatable). | Path |
| `--disallow-temp-dir` | Block access to the temp directory. | — |

```bash
# Full autopilot for a tedious refactor
copilot --yolo -p "Migrate src/ from moment.js to date-fns and run npm test"

# Narrow autopilot: only git, only write, only this directory
copilot \
  --allow-tool='shell(git:*)' \
  --allow-tool='write' \
  --add-dir ./packages/api \
  -p "Bring orders/ to 80% test coverage"

# Block destructive shell commands even under --yolo
copilot --yolo --deny-tool='shell(rm)' --deny-tool='shell(git push)' \
  -p "Clean up dead code in src/legacy"
```

---

## 🧠 Model & Reasoning

| Flag | Purpose | Values |
| --- | --- | --- |
| `--model <MODEL>` | Select the AI model. | Model name or `auto` |
| `--effort <LEVEL>` | Set reasoning effort. | `low`, `medium`, `high` |
| `--reasoning-effort <LEVEL>` | Alias for `--effort`. | `low`, `medium`, `high` |
| `--enable-reasoning-summaries` | Ask the agent to surface reasoning summaries. | — |

```bash
copilot --model claude-opus --effort high -p "Design a sharding plan for the orders table"
```

### Lower-tier model usage

For routine tasks — scaffolding, lint fixes, doc edits, simple refactors — pick a cheaper model to preserve premium-request quota for harder work. Use `auto` to let Copilot route per task, or pin an explicit model.

> Exact identifier strings vary by subscription tier and CLI version. Run `/model` inside the CLI (or `copilot --help`) to see the live list before scripting. The strings below match the model names listed in [GitHub's Copilot CLI changelog](https://github.blog/changelog/2025-10-03-github-copilot-cli-enhanced-model-selection-image-support-and-streamlined-ui/); confirm them against your install.

| Model | Best for | Premium-request multiplier |
| --- | --- | --- |
| **GPT-4.1** | Bulk edits, scaffolding, lint fixes, doc rewrites. Cost-efficient on paid plans. | ~0× (included) |
| **GPT-5.1** | Day-to-day coding, multi-file changes, mid-complexity reasoning. | ~1× |
| **Claude Sonnet 4.6** | Long-context refactors, careful diff review, code-review-style passes. Good default. | ~1× |
| `auto` | Let Copilot route per request. | varies |

```bash
# GPT-4.1 — cheap bulk doc/lint pass
copilot --model gpt-4.1 --effort low \
  --allow-tool='write' --add-dir ./docs \
  -p "Fix every markdown lint warning under docs/ and standardize heading levels"

# GPT-5.1 — routine multi-file refactor at default effort
copilot --model gpt-5.1 \
  --add-dir ./packages/api \
  -p "Extract the duplicated pagination logic in routes/ into a shared helper"

# Claude Sonnet 4.6 — careful refactor with rich diff review
copilot --model claude-sonnet-4.6 --effort medium \
  --add-dir ./packages/web \
  -p "Migrate the auth context from Redux to Zustand; preserve all existing call sites"

# auto — let Copilot pick per request
copilot --model auto -p "Investigate why the orders test suite is flaky"
```

**Combining with autopilot.** Lower-tier models pair well with bounded autopilot for repetitive work:

```bash
copilot --model gpt-4.1 \
  --autopilot --max-autopilot-continues 8 \
  --add-dir ./apps/web \
  --deny-tool='shell(git push)' \
  -p "Replace all React.FC usages with explicit prop types across apps/web"
```

**Env-var alternative.** Set the default model for the whole shell session instead of repeating `--model`:

```bash
export COPILOT_MODEL=gpt-4.1
copilot -p "Update every TODO comment in src/ to a GitHub issue link"
copilot -p "Add JSDoc to every exported function in lib/"
```

---

## 🤖 Agents, Plugins & Custom Instructions

| Flag | Purpose | Values |
| --- | --- | --- |
| `--agent <NAME>` | Use a specific custom agent. | Agent name |
| `--no-custom-instructions` | Skip loading `AGENTS.md`. | — |
| `--plugin-dir <DIR>` | Load a local plugin (repeatable). | Path |

```bash
copilot --agent code-review --plugin-dir ./tools/cleanup-plugin -p "Review the diff"
```

---

## 🧩 MCP Server Configuration

Wire Copilot up to Model Context Protocol servers (databases, internal tools, GitHub).

| Flag | Purpose | Values |
| --- | --- | --- |
| `--disable-builtin-mcps` | Disable all built-in MCP servers. | — |
| `--disable-mcp-server <NAME>` | Disable a specific MCP server (repeatable). | Server name |
| `--additional-mcp-config <JSON>` | Add an MCP server for this session. | JSON string or `@file` |
| `--add-github-mcp-tool <TOOL>` | Enable a GitHub MCP tool (repeatable). | Tool name or `*` |
| `--add-github-mcp-toolset <SET>` | Enable a GitHub MCP toolset (repeatable). | Toolset name or `all` |
| `--enable-all-github-mcp-tools` | Enable every GitHub MCP tool. | — |

```bash
copilot \
  --additional-mcp-config @./mcp/postgres-readonly.json \
  --add-github-mcp-toolset issues \
  -p "Triage the top 10 open bugs against the orders schema"
```

---

## 🖥 Display & Output

| Flag | Purpose | Values |
| --- | --- | --- |
| `--output-format <FORMAT>` | Output format. | `text`, `json` (JSONL) |
| `-s, --silent` | Print only the agent's final response. | — |
| `--no-color` | Disable color output. | — |
| `--plain-diff` | Plain-text diff instead of rich rendering. | — |
| `--banner` / `--no-banner` | Show / hide the startup banner. | — |
| `--mouse [VALUE]` | Mouse support. | `on`, `off` |
| `--no-mouse` | Disable mouse support. | — |
| `--screen-reader` | Enable accessibility-optimized output. | — |
| `--stream <MODE>` | Control streaming output. | `on`, `off` |

```bash
# CI-friendly invocation: silent, JSON, no color, no banner
copilot -s --no-color --no-banner --output-format json -p "Lint and report errors"
```

---

## 🪵 Logging & Diagnostics

| Flag | Purpose | Values |
| --- | --- | --- |
| `--log-level <LEVEL>` | Logging verbosity. | `none`, `error`, `warning`, `info`, `debug`, `all`, `default` |
| `--log-dir <DIR>` | Override the log directory. | Path |

```bash
copilot --log-level debug --log-dir ./.copilot-logs -p "Reproduce the auth bug"
```

---

## 🐚 Shell Integration

| Flag | Purpose | Values |
| --- | --- | --- |
| `--bash-env` / `--no-bash-env` | Enable / disable `BASH_ENV` support. | — |

---

## 🔒 Environment & Secrets

| Flag | Purpose | Values |
| --- | --- | --- |
| `--secret-env-vars <VAR>` | Redact an environment variable from logs and prompts (repeatable). | Variable name |

```bash
copilot --secret-env-vars STRIPE_SECRET_KEY --secret-env-vars DATABASE_URL -p "Smoke-test billing"
```

---

## 🧪 Features & Experiments

| Flag | Purpose | Values |
| --- | --- | --- |
| `--experimental` / `--no-experimental` | Toggle experimental features. | — |

---

## 📤 Session Export

| Flag | Purpose | Values |
| --- | --- | --- |
| `--share <PATH>` | Export the session to Markdown after completion. | File path |
| `--share-gist` | Export the session to a secret GitHub gist. | — |

```bash
copilot -p "Investigate the slow checkout query" --share ./.sessions/checkout-perf.md
copilot -p "Reproduce the flaky test" --share-gist
```

---

## 📦 Updates & Info

| Flag | Purpose | Values |
| --- | --- | --- |
| `-v, --version` | Print version. | — |
| `-h, --help` | Print help. | — |
| `--no-auto-update` | Disable automatic updates for this run. | — |

---

## End-to-End Recipes

### 1. CI lint-and-fix step

```bash
copilot \
  --no-banner --no-color -s \
  --output-format json \
  --allow-tool='shell(npm:*)' --allow-tool='write' \
  --deny-tool='shell(git push)' \
  --add-dir . \
  --log-level error \
  -p "Run npm run lint, fix every auto-fixable error, and exit non-zero if any remain"
```

### 2. Scoped autopilot refactor

```bash
copilot \
  --autopilot --max-autopilot-continues 10 \
  --add-dir ./packages/api \
  --deny-tool='shell(rm)' --deny-tool='shell(git push)' \
  --share ./.sessions/orders-refactor.md \
  -p "Replace the home-grown retry helper with p-retry across packages/api"
```

### 3. Plan-first feature work

```bash
copilot --plan --model claude-opus --effort high \
  -n "stripe-checkout" \
  -p "Design and implement Stripe Checkout on the cart page with webhook fulfillment"
# review the plan, then in a new shell:
copilot --resume stripe-checkout --autopilot
```

### 4. Remote-steerable long-running task

```bash
copilot --remote --autopilot \
  -n "schema-migration-2026-05" \
  -p "Run the orders-table sharding migration and verify row counts"
# Monitor and steer from github.com or the GitHub Mobile app.
```

---

## See Also

- `copilot --help` — live flag list for the installed version.
- [Configuring GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/configure-copilot-cli)
- [Using GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/use-copilot-agents/use-copilot-cli)
- [Responsible use of GitHub Copilot CLI](https://docs.github.com/en/copilot/responsible-use/copilot-cli)
