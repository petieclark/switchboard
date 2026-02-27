#!/bin/bash
# Usage: msg-inbox.sh <agent_name> [--all]
AGENT="${1:?Agent name required}"
BOARD_URL="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"
UNREAD_ONLY="${2:---unread}"

if [ "$2" = "--all" ]; then
  URL="$BOARD_URL/messages?to_agent=$AGENT&limit=20"
else
  URL="$BOARD_URL/messages?to_agent=$AGENT&unread_only=true&limit=20"
fi

DATA=$(curl -sf "$URL")
if [ -z "$DATA" ]; then echo "AgentBoard unreachable"; exit 1; fi

echo "$DATA" | python3 -c "
import json, sys
msgs = json.load(sys.stdin)
if not msgs:
    print('No messages.')
    sys.exit(0)
for m in reversed(msgs):
    tag = '' if m['read'] else '[NEW] '
    task = f' (task #{m[\"task_id\"]})' if m.get('task_id') else ''
    print(f'{tag}from {m[\"from_agent\"]}{task}: {m[\"content\"]}')
    print(f'  at {m[\"created_at\"][:19]}Z')
    print()
"
