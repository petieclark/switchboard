#!/bin/bash
# Usage: msg-send.sh <from_agent> <content> [to_agent] [task_id]
FROM="${1:?from_agent required}"
CONTENT="${2:?content required}"
TO="${3:-}"
TASK_ID="${4:-}"
BOARD_URL="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

PAYLOAD=$(python3 -c "
import json, sys
d = {'from_agent': sys.argv[1], 'content': sys.argv[2]}
if sys.argv[3]: d['to_agent'] = sys.argv[3]
if sys.argv[4]: d['task_id'] = int(sys.argv[4])
print(json.dumps(d))
" "$FROM" "$CONTENT" "$TO" "$TASK_ID")

curl -sf -X POST "$BOARD_URL/messages" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | python3 -m json.tool --no-ensure-ascii
