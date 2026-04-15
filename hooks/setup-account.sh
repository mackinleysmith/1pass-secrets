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

# List accounts
accounts_json=$(op account list --format json 2>/dev/null) || exit 0
count=$(echo "$accounts_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null) || exit 0

[ "$count" = "0" ] && exit 0

settings_file="$HOME/.claude/settings.json"

select_account() {
  local url="$1"

  # Ensure settings.json exists
  if [ ! -f "$settings_file" ]; then
    echo "{}" > "$settings_file"
  fi

  # Merge OP_ACCOUNT into the env block
  python3 -c "
import json, sys
try:
    with open('$settings_file') as f:
        s = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    s = {}
s.setdefault('env', {})['OP_ACCOUNT'] = '$url'
with open('$settings_file', 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
" 2>/dev/null || return 1
}

if [ "$count" = "1" ]; then
  url=$(echo "$accounts_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['url'])" 2>/dev/null)
  if [ -n "$url" ] && select_account "$url"; then
    echo "1pass-secrets: Auto-configured OP_ACCOUNT=$url"
  fi
else
  # Multiple accounts — build a list for macOS picker, fall back to message
  urls=$(echo "$accounts_json" | python3 -c "
import sys, json
for a in json.load(sys.stdin):
    print(a['url'])
" 2>/dev/null)

  if command -v osascript &>/dev/null; then
    # Build AppleScript list string: {"url1", "url2", ...}
    as_list=$(echo "$urls" | python3 -c "
import sys
urls = [line.strip() for line in sys.stdin if line.strip()]
print('{' + ', '.join('\"' + u + '\"' for u in urls) + '}')
" 2>/dev/null)

    selected=$(osascript -e "choose from list $as_list with prompt \"Select 1Password account for Claude Code:\" with title \"1pass-secrets setup\"" 2>/dev/null)

    # User clicked Cancel
    [ "$selected" = "false" ] || [ -z "$selected" ] && exit 0

    if select_account "$selected"; then
      echo "1pass-secrets: Configured OP_ACCOUNT=$selected"
    fi
  else
    echo "1pass-secrets: Multiple 1Password accounts detected. Set OP_ACCOUNT in ~/.claude/settings.json:"
    echo "  { \"env\": { \"OP_ACCOUNT\": \"youraccount.1password.com\" } }"
    echo "Available accounts:"
    echo "$urls" | sed 's/^/  - /'
  fi
fi
