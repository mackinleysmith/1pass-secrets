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
