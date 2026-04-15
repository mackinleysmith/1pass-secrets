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

command -v op &>/dev/null || { echo "ERROR: op CLI not found. Install with: brew install --cask 1password-cli" >&2; exit 1; }

# Resolve the Claude Code process PID (grandparent: Claude Code → shell → this script)
session_pid=$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ')
[ -z "$session_pid" ] && session_pid=$PPID
hash=$(echo -n "$item_name" | shasum -a 256 | cut -d' ' -f1)
cache_file="/tmp/.claude-secrets-${session_pid}-${hash}"

# Return cached value if available
if [ -s "$cache_file" ]; then
  cat "$cache_file"
  exit 0
fi

# Fetch from 1Password, cache, and return
op_err=$(mktemp /tmp/.claude-op-err-XXXXXX)
if ! value=$(op read "op://claude-code/${item_name}/credential" 2>"$op_err"); then
  echo "ERROR: Failed to read '${item_name}' from 1Password: $(cat "$op_err")" >&2
  rm -f "$op_err"
  rm -f "$cache_file"
  exit 1
fi

rm -f "$op_err"
( umask 177 && echo -n "$value" > "$cache_file" )
echo -n "$value"
