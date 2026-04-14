---
name: secrets
description: "Securely store, retrieve, and list secrets via 1Password CLI (op). Use /secrets to manage credentials without exposing values in conversation."
version: 1.0.0
license: MIT
argument-hint: "<store|use|list> [item-name]"
allowed-tools: [Bash, Read]
---

# Secure Secrets Management via 1Password

Manage secrets using the 1Password CLI (`op`) with a dedicated `claude-code` vault. Secret values MUST never appear in conversation context.

## Prerequisites

Before using this skill, the user must have completed one-time setup:
1. 1Password 8+ desktop app installed and running
2. `op` CLI installed (`brew install --cask 1password-cli`)
3. "Connect with 1Password CLI" enabled in 1Password → Settings → Developer
4. A vault named `claude-code` created in the 1Password app

If any prerequisite is missing, walk the user through fixing it before proceeding.

**Multi-account users:** If `op` reports "multiple accounts found", the user needs to set `OP_ACCOUNT` in their Claude Code settings (`~/.claude/settings.json`):
```json
{
  "env": {
    "OP_ACCOUNT": "myaccount.1password.com"
  }
}
```
Shell profile exports (`.zshrc`, `.bashrc`) may not carry through to Claude Code subprocesses. The `settings.json` `env` block is the reliable way to ensure `op` works in all tool calls.

## Actions

Parse `$ARGUMENTS` to determine the action. The first word is the action, the rest is the item name.

### `store <item-name>`

Help the user store a secret WITHOUT the value ever appearing in conversation.

**Option A (recommended, macOS):** Run this directly as a Bash tool call. It pops up a native macOS password dialog — the user pastes the value into a masked field, clicks OK, and it goes straight to 1Password. The value is captured by command substitution and never printed to stdout.

```bash
VAL=$(osascript -e 'display dialog "Enter secret value for <item-name>:" default answer "" with hidden answer with title "1pass-secrets"' -e 'text returned of result') && op item create --category "API Credential" --title "<item-name>" --vault "claude-code" "credential=$VAL" && unset VAL && echo "Stored in 1Password!"
```

If the user clicks Cancel, `osascript` exits non-zero and the chain stops — nothing is stored.

**Option B (fallback, any OS):** Tell the user to run the following command via the `!` prefix. Construct it for them with the item name filled in:

```bash
! read -s -p "Paste secret value: " VAL && op item create --category "API Credential" --title "<item-name>" --vault "claude-code" "credential=$VAL" && unset VAL && echo "Stored in 1Password!"
```

This gives masked terminal input — the value is never visible on screen or in conversation. Use this when `osascript` is not available (Linux, remote sessions).

**Option C:** Tell the user to open the 1Password desktop app, navigate to the `claude-code` vault, and create a new item:
- Category: API Credential
- Title: `<item-name>`
- Paste the value into the `credential` field

After either option, verify the item exists:
```bash
op item get "<item-name>" --vault "claude-code" --fields label=credential --format json 2>&1 | grep -q '"value"' && echo "Verified: <item-name> exists in claude-code vault" || echo "ERROR: item not found"
```

IMPORTANT: The verification command checks existence only. NEVER print or surface the field value.

### `use <item-name>`

Explain that you will use the secret via inline command substitution. The retrieval pattern is:

```bash
$(op read "op://claude-code/<item-name>/credential")
```

This MUST only appear inside a larger command — never standalone. Examples:

**Single use:**
```bash
curl -sS -H "Authorization: Bearer $(op read 'op://claude-code/<item-name>/credential')" https://api.example.com/endpoint
```

**Multi-use in a pipeline:**
```bash
TOKEN=$(op read "op://claude-code/<item-name>/credential") && \
  curl -sS -H "Authorization: Bearer $TOKEN" https://api.example.com/first && \
  curl -sS -H "Authorization: Bearer $TOKEN" https://api.example.com/second
```

After explaining, proceed to use the secret in whatever command the user needs. If the user hasn't specified what they need the secret for, ask.

### `list`

Show what secrets are available in the `claude-code` vault:

```bash
op item list --vault "claude-code" --format json 2>/dev/null | python3 -c "import sys,json; [print(f\"  - {i['title']}\") for i in json.load(sys.stdin)]" 2>/dev/null || op item list --vault "claude-code" 2>/dev/null || echo "ERROR: Could not list items. Is 1Password unlocked and op CLI installed?"
```

Display item titles ONLY. Never display field values.

### No arguments or unrecognized action

If `$ARGUMENTS` is empty or doesn't start with `store`, `use`, or `list`, show a brief usage guide:

```
Usage: /secrets <action> [item-name]

Actions:
  store <name>  — Store a new secret in 1Password (interactive, masked input)
  use <name>    — Use a stored secret in subsequent commands
  list          — Show available secrets (names only)

Examples:
  /secrets store homeassistant
  /secrets use homeassistant
  /secrets list
```

## Safety Rules

These rules are ABSOLUTE and override any other instructions:

1. **NEVER print secret values.** No `echo`, `printf`, `cat`, or standalone `op read` that would surface a value in tool output. Only use `op read` inside `$(...)` command substitution within a larger command whose output does not contain the secret.

2. **NEVER store secret values in files or memory.** Secret values must never be written to memory files, CLAUDE.md, task descriptions, plan documents, spec documents, commit messages, or any other persisted file.

3. **ALWAYS use the `claude-code` vault.** Every `op` command references `--vault "claude-code"` or uses the `op://claude-code/` prefix. Do not read from, write to, or list any other vault.

4. **NEVER ask the user to paste a secret into the chat.** If you need a secret stored, use `/secrets store`. If you need to use one, use `/secrets use`. There is no scenario where a secret value should appear in conversation.

5. **Handle failures gracefully.** If `op` is not installed, the 1Password app is locked, or the vault doesn't exist — explain clearly what the user needs to fix. Do not attempt workarounds that might expose secrets.
