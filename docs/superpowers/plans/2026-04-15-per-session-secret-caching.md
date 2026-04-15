# Per-Session Secret Caching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cache `op read` results in per-session temp files so each secret only requires one Touch ID prompt per session.

**Architecture:** A shell script (`bin/secret-cache.sh`) wraps the cache-or-fetch logic. SKILL.md's `use` action calls this helper instead of raw `op read`. A Stop hook deletes cache files on session end; a stale sweep in the SessionStart hook catches crash orphans.

**Tech Stack:** Bash, 1Password CLI (`op`), `shasum`, Claude Code plugin hooks

**Spec:** `docs/superpowers/specs/2026-04-15-per-session-secret-caching-design.md`

---

### Task 1: Create `bin/secret-cache.sh`

**Files:**
- Create: `bin/secret-cache.sh`

This is the core component. It takes a secret name, checks for a cached value, and either returns it from cache or fetches via `op read`, caches, and returns.

- [ ] **Step 1: Create `bin/secret-cache.sh`**

```bash
#!/bin/bash
# 1pass-secrets: cache-or-fetch helper for per-session secret caching.
# Usage: secret-cache.sh <item-name>
# stdout: the secret value
# stderr: diagnostics/errors only
# Exit 0 on success, 1 on failure.

set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "Usage: secret-cache.sh <item-name>" >&2
  exit 1
fi

item_name="$1"
hash=$(echo -n "$item_name" | shasum -a 256 | cut -d' ' -f1)
cache_file="/tmp/.claude-secrets-${PPID}-${hash}"

# Return cached value if available
if [ -s "$cache_file" ]; then
  cat "$cache_file"
  exit 0
fi

# Fetch from 1Password, cache, and return
if ! value=$(op read "op://claude-code/${item_name}/credential" 2>/dev/null); then
  echo "ERROR: Failed to read '${item_name}' from 1Password. Is the app unlocked?" >&2
  rm -f "$cache_file"
  exit 1
fi

echo -n "$value" > "$cache_file"
chmod 600 "$cache_file"
echo -n "$value"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x bin/secret-cache.sh`

- [ ] **Step 3: Verify argument validation**

Run: `bin/secret-cache.sh`
Expected: stderr shows `Usage: secret-cache.sh <item-name>`, exit code 1.

Run: `bin/secret-cache.sh ""`
Expected: same usage error, exit code 1.

- [ ] **Step 4: Verify cache-miss path (requires 1Password unlocked and a test secret)**

If you have a test secret in the `claude-code` vault, run:
```bash
bin/secret-cache.sh <test-secret-name>
```
Expected: Touch ID prompt, then the secret value on stdout. A cache file appears at `/tmp/.claude-secrets-${PPID}-<hash>`.

Verify the cache file:
```bash
hash=$(echo -n "<test-secret-name>" | shasum -a 256 | cut -d' ' -f1)
ls -la "/tmp/.claude-secrets-${PPID}-${hash}"
```
Expected: file exists, permissions `-rw-------`.

- [ ] **Step 5: Verify cache-hit path**

Run the same command again:
```bash
bin/secret-cache.sh <test-secret-name>
```
Expected: same value returned instantly, no Touch ID prompt.

- [ ] **Step 6: Clean up test cache file and commit**

```bash
rm -f /tmp/.claude-secrets-${PPID}-*
git add bin/secret-cache.sh
git commit -m "feat: add secret-cache.sh cache-or-fetch helper"
```

---

### Task 2: Create `hooks/cleanup-cache.sh` (Stop hook)

**Files:**
- Create: `hooks/cleanup-cache.sh`

Deletes all cache files for the current session on normal exit.

- [ ] **Step 1: Create `hooks/cleanup-cache.sh`**

```bash
#!/bin/bash
# 1pass-secrets: clean up cached secrets on session end.
# Runs as a Stop hook. Exits 0 regardless — cleanup failure must not block teardown.

rm -f /tmp/.claude-secrets-${PPID}-* 2>/dev/null
exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x hooks/cleanup-cache.sh`

- [ ] **Step 3: Verify it deletes matching files**

Create dummy cache files and run the script:
```bash
touch /tmp/.claude-secrets-${PPID}-aaa /tmp/.claude-secrets-${PPID}-bbb
ls /tmp/.claude-secrets-${PPID}-*
hooks/cleanup-cache.sh
ls /tmp/.claude-secrets-${PPID}-* 2>&1
```
Expected: first `ls` shows two files; after running the script, second `ls` reports "No such file or directory".

- [ ] **Step 4: Verify it doesn't touch other sessions' files**

```bash
touch /tmp/.claude-secrets-99999-aaa
hooks/cleanup-cache.sh
ls /tmp/.claude-secrets-99999-aaa
```
Expected: file still exists (different PID). Clean up: `rm -f /tmp/.claude-secrets-99999-aaa`

- [ ] **Step 5: Commit**

```bash
git add hooks/cleanup-cache.sh
git commit -m "feat: add cleanup-cache.sh Stop hook for session teardown"
```

---

### Task 3: Add stale cache sweep to `hooks/setup-account.sh`

**Files:**
- Modify: `hooks/setup-account.sh:1-5` (insert stale sweep before existing logic)

The SessionStart hook already runs on every session. Add a sweep at the top that deletes cache files belonging to dead processes.

- [ ] **Step 1: Add stale sweep to the top of `hooks/setup-account.sh`**

Insert the following block after the shebang and comment, before the `[ -n "$OP_ACCOUNT" ]` line:

```bash
# Clean up stale cache files from crashed sessions
for f in /tmp/.claude-secrets-*; do
  [ -e "$f" ] || continue
  pid=$(basename "$f" | sed 's/^\.claude-secrets-\([0-9]*\)-.*/\1/')
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"
  fi
done
```

The full file after the edit should read:

```bash
#!/bin/bash
# 1pass-secrets: auto-detect and configure OP_ACCOUNT on session start.
# Runs silently if op is not installed or account is already configured.

# Clean up stale cache files from crashed sessions
for f in /tmp/.claude-secrets-*; do
  [ -e "$f" ] || continue
  pid=$(basename "$f" | sed 's/^\.claude-secrets-\([0-9]*\)-.*/\1/')
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"
  fi
done

# Already configured — nothing to do
[ -n "$OP_ACCOUNT" ] && exit 0

# op not installed — nothing to do
command -v op &>/dev/null || exit 0

# ... rest of existing file unchanged ...
```

- [ ] **Step 2: Verify sweep deletes orphaned files**

```bash
touch /tmp/.claude-secrets-99999-aaa /tmp/.claude-secrets-99998-bbb
hooks/setup-account.sh
ls /tmp/.claude-secrets-99999-aaa 2>&1
ls /tmp/.claude-secrets-99998-bbb 2>&1
```
Expected: both files deleted (PIDs 99999 and 99998 are not running).

- [ ] **Step 3: Verify sweep preserves files from live processes**

```bash
touch /tmp/.claude-secrets-1-aaa
hooks/setup-account.sh
ls /tmp/.claude-secrets-1-aaa
```
Expected: file still exists (PID 1 is launchd, always alive). Clean up: `rm -f /tmp/.claude-secrets-1-aaa`

- [ ] **Step 4: Commit**

```bash
git add hooks/setup-account.sh
git commit -m "feat: add stale cache sweep to SessionStart hook"
```

---

### Task 4: Register Stop hook in `hooks/hooks.json`

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Update `hooks/hooks.json` to add the Stop hook**

Replace the full file contents with:

```json
{
  "description": "Auto-detect 1Password account on session start; clean up cached secrets on session end",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/setup-account.sh\"",
            "timeout": 15000
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/cleanup-cache.sh\"",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON**

Run: `python3 -c "import json; json.load(open('hooks/hooks.json'))"`
Expected: no output (valid JSON).

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: register cleanup-cache.sh as Stop hook"
```

---

### Task 5: Update SKILL.md `use` action

**Files:**
- Modify: `skills/secrets/SKILL.md:70-91` (the `use` action section)

- [ ] **Step 1: Update the `use` action**

In `skills/secrets/SKILL.md`, replace the `use` action section. The retrieval pattern changes from `op read` to the cache helper. Replace the section starting at `### \`use <item-name>\`` with:

````markdown
### `use <item-name>`

Explain that you will use the secret via inline command substitution with per-session caching. The first retrieval triggers a Touch ID prompt; subsequent uses within the same session are served from cache.

The retrieval pattern is:

```bash
$("${CLAUDE_PLUGIN_ROOT}/bin/secret-cache.sh" "<item-name>")
```

This MUST only appear inside a larger command — never standalone. Examples:

**Single use:**
```bash
curl -sS -H "Authorization: Bearer $("${CLAUDE_PLUGIN_ROOT}/bin/secret-cache.sh" "<item-name>")" https://api.example.com/endpoint
```

**Multi-use in a pipeline:**
```bash
TOKEN=$("${CLAUDE_PLUGIN_ROOT}/bin/secret-cache.sh" "<item-name>") && \
  curl -sS -H "Authorization: Bearer $TOKEN" https://api.example.com/first && \
  curl -sS -H "Authorization: Bearer $TOKEN" https://api.example.com/second
```

After explaining, proceed to use the secret in whatever command the user needs. If the user hasn't specified what they need the secret for, ask.
````

- [ ] **Step 2: Verify SKILL.md has no references to raw `op read` in the `use` section**

Run: `sed -n '/### .use/,/### /p' skills/secrets/SKILL.md | grep 'op read'`
Expected: no output (no raw `op read` left in the `use` action).

Note: `op read` references in the `store` action's verification step and the general description are fine — those are unrelated to the `use` flow.

- [ ] **Step 3: Commit**

```bash
git add skills/secrets/SKILL.md
git commit -m "feat: update /secrets use to call cache helper instead of raw op read"
```

---

### Task 6: Bump version and update README

**Files:**
- Modify: `.claude-plugin/plugin.json` (version bump)
- Modify: `README.md` (document caching)

- [ ] **Step 1: Bump version in `plugin.json`**

Change `"version": "1.1.0"` to `"version": "1.2.0"`.

- [ ] **Step 2: Add caching section to README**

In `README.md`, add a new section after `## Usage` and before `## Security model`:

```markdown
## Per-session caching

The first time you use a secret in a session, 1Password prompts for biometric auth (Touch ID). After that, the secret value is cached locally for the remainder of the session — subsequent uses of the same secret skip the Touch ID prompt.

- Each secret is approved individually on first use
- Cache files are stored in `/tmp` with `chmod 600` permissions
- Files are automatically deleted when the session ends
- Stale cache files from crashed sessions are cleaned up on next session start

No configuration needed — caching is automatic.
```

- [ ] **Step 3: Update the security model section in README**

Add a new bullet to the `## Security model` section:

```markdown
- **Session cache:** Cached secret values are stored in `/tmp` with restrictive permissions (`chmod 600`) and hashed filenames. Files are cleaned up on session end and on next session start if a previous session crashed.
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json README.md
git commit -m "chore: bump version to 1.2.0, document per-session caching in README"
```

---

### Task 7: End-to-end verification

No files changed in this task — this is a manual verification pass.

- [ ] **Step 1: Verify file structure**

Run: `find . -type f -not -path './.git/*' | sort`

Expected output should include:
```
./.claude-plugin/marketplace.json
./.claude-plugin/plugin.json
./LICENSE
./README.md
./bin/secret-cache.sh
./docs/superpowers/plans/2026-04-15-per-session-secret-caching.md
./docs/superpowers/specs/2026-04-15-per-session-secret-caching-design.md
./hooks/cleanup-cache.sh
./hooks/hooks.json
./hooks/setup-account.sh
./skills/secrets/SKILL.md
```

- [ ] **Step 2: Verify executables**

Run: `ls -la bin/secret-cache.sh hooks/cleanup-cache.sh hooks/setup-account.sh`
Expected: all three have execute bit set (`-rwxr-xr-x` or similar).

- [ ] **Step 3: Verify hooks.json is valid and has both hooks**

Run: `python3 -c "import json; d=json.load(open('hooks/hooks.json')); assert 'SessionStart' in d['hooks']; assert 'Stop' in d['hooks']; print('OK')"`
Expected: `OK`

- [ ] **Step 4: Verify plugin version**

Run: `python3 -c "import json; d=json.load(open('.claude-plugin/plugin.json')); assert d['version']=='1.2.0'; print('OK')"`
Expected: `OK`

- [ ] **Step 5: Full cache lifecycle test (requires 1Password unlocked and a test secret)**

```bash
# 1. Fetch secret (should trigger Touch ID)
value1=$(bin/secret-cache.sh <test-secret-name>)
echo "Got value: [redacted, length=${#value1}]"

# 2. Fetch again (should be instant, no Touch ID)
value2=$(bin/secret-cache.sh <test-secret-name>)
echo "Cache hit: [redacted, length=${#value2}]"

# 3. Verify values match
[ "$value1" = "$value2" ] && echo "PASS: values match" || echo "FAIL: values differ"

# 4. Verify cache file exists with correct permissions
hash=$(echo -n "<test-secret-name>" | shasum -a 256 | cut -d' ' -f1)
ls -la "/tmp/.claude-secrets-${PPID}-${hash}"

# 5. Run cleanup
hooks/cleanup-cache.sh
ls "/tmp/.claude-secrets-${PPID}-${hash}" 2>&1
echo "PASS: cleanup removed cache file"
```

- [ ] **Step 6: Create final version tag**

```bash
git tag v1.2.0
```
