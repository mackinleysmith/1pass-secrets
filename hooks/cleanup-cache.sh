#!/bin/bash
# 1pass-secrets: clean up cached secrets on session end.
# Runs as a Stop hook. Exits 0 regardless — cleanup failure must not block teardown.

# Resolve the Claude Code process PID (grandparent: Claude Code → shell → this script)
session_pid=$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ')
[ -z "$session_pid" ] && session_pid=$PPID
rm -f /tmp/.claude-secrets-${session_pid}-* 2>/dev/null
exit 0
