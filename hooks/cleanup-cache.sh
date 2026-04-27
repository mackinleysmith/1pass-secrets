#!/bin/bash
# 1pass-secrets: clean up cached secrets on session end.
# Runs as a SessionEnd hook. Exits 0 regardless — cleanup failure must not block teardown.

# Walk up the process tree to find the Claude Code ancestor's PID — must match
# the identity scheme in bin/secret-cache.sh so we delete the right files.
session_pid=""
pid=$PPID
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -z "$pid" ] || [ "$pid" -le 1 ] && break
  if [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "claude" ]; then
    session_pid=$pid
    break
  fi
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
done

# Only delete if we resolved a real Claude Code PID — never fall back and
# risk wiping another session's cache.
[ -n "$session_pid" ] && rm -f /tmp/.claude-secrets-${session_pid}-* 2>/dev/null
exit 0
