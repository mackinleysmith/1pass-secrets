# Per-Session Secret Caching

## Problem

Each `op read` in a Claude Code Bash tool call triggers a fresh 1Password CLI invocation, which prompts for biometric auth (Touch ID). Since every Bash tool call is a fresh shell with no persistent environment, a session that uses the same secret across multiple tool calls forces repeated Touch ID prompts — one per invocation. This creates significant friction for workflows that reference secrets frequently (e.g., multiple API calls using the same deploy key).

## Solution

Cache secret values in per-session temp files on first retrieval. Subsequent uses of the same secret within the session read from cache, bypassing `op read` and its Touch ID prompt. Each distinct secret still requires one initial Touch ID approval — this is per-secret, per-session caching, not blanket access.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Cache population | Lazy (on first use) | Simplest; no new commands; caching is invisible to the user |
| Storage mechanism | Temp files in `/tmp`, `chmod 600` | Works across fresh shells; matches existing threat model |
| Cleanup strategy | Stop hook + SessionStart sweep | Stop hook handles normal exit; sweep catches crash orphans |
| Session identity | `$PPID` | Stable across Bash tool calls; identifies the Claude Code process |
| Filename format | Hashed secret names (SHA-256) | Avoids leaking item names in `/tmp` listings |

## File Layout

All changes are within the plugin directory tree. Uninstall = remove the plugin; nothing is scattered across the system.

```
1pass-secrets/
├── .claude-plugin/
│   └── plugin.json              # bump version to 1.2.0
├── hooks/
│   ├── hooks.json               # add Stop hook entry
│   ├── setup-account.sh         # add stale cache sweep at top
│   └── cleanup-cache.sh         # NEW — Stop hook
├── bin/
│   └── secret-cache.sh          # NEW — cache-or-fetch helper
├── skills/
│   └── secrets/
│       └── SKILL.md             # update `use` action to call helper
└── README.md                    # document caching behavior
```

## Components

### `bin/secret-cache.sh`

Cache-or-fetch helper. Takes a secret name, returns the value.

**Interface:**
```
secret-cache.sh <item-name>
# stdout: the secret value
# exit 0: success
# exit 1: failure
```

**Logic:**
1. Validate: require exactly one argument.
2. Compute cache path: `hash=$(echo -n "$1" | shasum -a 256 | cut -d' ' -f1)`, file = `/tmp/.claude-secrets-${PPID}-${hash}`.
3. If cache file exists and is non-empty, `cat` it and exit.
4. Otherwise, `op read "op://claude-code/$1/credential"` into the file, `chmod 600`, then `cat` it.
5. If `op read` fails, delete any partial file and propagate the error.

**Constraints:**
- Diagnostic messages go to stderr only; stdout is exclusively the secret value.
- `$PPID` in this script context = the Claude Code process PID.

### `hooks/cleanup-cache.sh` (new Stop hook)

- Deletes all `/tmp/.claude-secrets-${PPID}-*` files.
- Silent on success; errors to stderr.
- Exits 0 regardless — cleanup failure must not block session teardown.

### `hooks/hooks.json` update

Add a `Stop` entry alongside the existing `SessionStart`, pointing to `cleanup-cache.sh`.

### `hooks/setup-account.sh` update (stale sweep)

Before the existing account detection logic, add a sweep:
- For each file matching `/tmp/.claude-secrets-*`, extract the PID from the filename.
- Check if that PID is still alive (`kill -0 $pid 2>/dev/null`).
- Delete the file if the process is gone.

This catches crash orphans from previous sessions.

### SKILL.md update

Only the `use` action changes. The inline substitution pattern becomes:

```bash
$("${CLAUDE_PLUGIN_ROOT}/bin/secret-cache.sh" "<item-name>")
```

instead of:

```bash
$(op read "op://claude-code/<item-name>/credential")
```

The multi-use pipeline pattern (`TOKEN=$(...) && curl ... && curl ...`) still works and is still preferred when the same secret is used multiple times in one Bash call.

`store`, `list`, safety rules, and prerequisites are unchanged.

## Security Model

- **File permissions:** `chmod 600` — only the owning user can read/write.
- **`/tmp` sticky bit:** Other users cannot delete or rename files.
- **Hashed filenames:** SHA-256 of secret name; item names not leaked in directory listings.
- **Session-scoped lifetime:** Stop hook cleans up on normal exit; SessionStart sweep catches crash orphans.
- **Worst case (crash, no new session before reboot):** Plaintext secrets in `/tmp` until macOS clears it on restart. This matches 1Password's own threat model of keeping decrypted values in process memory.
- **No new attack surface:** The Bash tool already captures secret values in output via inline `$(op read ...)`. The cache file is the same value persisted to disk with restrictive permissions.
- **Safety rules unchanged:** Claude still never prints, stores in memory/plans, or surfaces secret values in conversation.

## Out of Scope

- **Cache invalidation within a session:** If a secret is rotated in 1Password mid-session, the cached value is stale until the next session. Acceptable; rotating a secret mid-session is rare.
- **`/secrets uncache` or `/secrets refresh` command:** YAGNI. Easy to add later if needed.
- **Encryption of cache files:** Would require a key management scheme that adds complexity without meaningfully changing the security posture.
- **Changes to `store` or `list`:** Only `use` is affected.
