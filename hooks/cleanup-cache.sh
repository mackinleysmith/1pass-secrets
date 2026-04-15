#!/bin/bash
# 1pass-secrets: clean up cached secrets on session end.
# Runs as a Stop hook. Exits 0 regardless — cleanup failure must not block teardown.

rm -f /tmp/.claude-secrets-${PPID}-* 2>/dev/null
exit 0
