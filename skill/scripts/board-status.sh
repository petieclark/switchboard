#!/bin/bash
# Usage: board-status.sh [--raw]
# Prints a human-readable board summary
BOARD_URL="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

DATA=$(curl -sf "$BOARD_URL/board")
if [ -z "$DATA" ]; then echo "AgentBoard unreachable"; exit 1; fi

if [ "$1" = "--raw" ]; then
  echo "$DATA" | python3 -m json.tool --no-ensure-ascii
  exit 0
fi

echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
totals = d.get('totals', {})
agents = d.get('agents', [])
unread = d.get('unread_messages', 0)

print('=== AgentBoard ===')
print()
print('AGENTS:')
for a in agents:
    print(f'  {a[\"name\"]:12s}  {a[\"status\"]}  (last seen: {a[\"last_heartbeat\"][:19]}Z)')

print()
print('TASKS BY STATUS:')
order = ['inbox','todo','in_progress','review','done','failed','blocked']
for s in order:
    c = totals.get(s, 0)
    if c: print(f'  {s:15s}  {c}')

if unread:
    print()
    print(f'⚠  {unread} unread message(s)')
"
