# 1pass-secrets

Secure secret management for Claude Code via 1Password CLI.

## What this does

Provides a `/secrets` slash command that lets Claude Code store, retrieve, and list secrets using the 1Password CLI (`op`). Secret values never enter the LLM conversation context — they're stored interactively with masked input and retrieved via inline command substitution.

## Prerequisites

- 1Password 8+ desktop app
- 1Password CLI: `brew install --cask 1password-cli`
- Enable "Connect with 1Password CLI" in 1Password → Settings → Developer
- Verify with: `op vault list`
- **Multiple 1Password accounts?** Add `OP_ACCOUNT` to your Claude Code settings (`~/.claude/settings.json`):
  ```json
  { "env": { "OP_ACCOUNT": "myaccount.1password.com" } }
  ```
  Shell profile exports (`.zshrc`) may not carry through to Claude Code subprocesses — the `settings.json` `env` block is the reliable method.

## One-time setup

Create a vault named `claude-code` in the 1Password app: Vaults → New Vault → name it `claude-code`.

This vault is where all secrets managed by this plugin are stored.

## Installation

```bash
claude plugin marketplace add mackinleysmith/1pass-secrets
claude plugin install 1pass-secrets
```

## Usage

**Store a secret:**

```
/secrets store homeassistant
```

Prompts you to enter a secret value with masked input. The value is written directly to 1Password and never passed through the LLM.

**Use a secret in a command:**

```
/secrets use homeassistant
```

Retrieves the secret via inline command substitution and injects it into a shell command. The value is cached for the session after the first retrieval. The value appears only in the subprocess environment, not in the conversation.

**List available secrets:**

```
/secrets list
```

Shows all items stored in the `claude-code` vault by name. Values are not shown.

## Per-session caching

The first time you use a secret in a session, 1Password prompts for biometric auth (Touch ID). After that, the secret value is cached locally for the remainder of the session — subsequent uses of the same secret skip the Touch ID prompt.

- Each secret is approved individually on first use
- Cache files are stored in `/tmp` with `chmod 600` permissions
- Files are automatically deleted when the session ends
- Stale cache files from crashed sessions are cleaned up on next session start

No configuration needed — caching is automatic.

## Security model

- **Vault scoping by convention:** The agent only accesses `op://claude-code/...` paths. Secrets in other vaults are not referenced.
- **Values never in LLM context:** During normal use, secret values are handled outside the conversation via command substitution or masked terminal input.
- **Biometric auth:** 1Password desktop app handles authentication — a human must approve access via Touch ID or password before the CLI can read any secret.
- **Auditable:** All 1Password CLI access is logged in the 1Password activity log.
- **Session cache:** Cached secret values are stored in `/tmp` with restrictive permissions (`chmod 600`) and hashed filenames. Files are cleaned up on session end and on next session start if a previous session crashed.
- **Plan compatibility:** Works with all 1Password plan types — Individual, Families, Teams, and Business.

## Limitations

- **Convention-enforced, not platform-enforced:** On Individual and Families plans, the `op` CLI technically has access to all vaults, not just `claude-code`. The scoping is enforced by how the skill is written, not by the platform. Teams and Business plans support service accounts, which can add platform-level vault restrictions.
- **Prompt injection risk:** A sufficiently crafted prompt injection could theoretically instruct the agent to surface a secret value. The safety rules in this plugin mitigate but do not eliminate this risk.
- **Requires desktop app:** The 1Password desktop app must be running and unlocked for CLI authentication to work.

## License

MIT
