#!/bin/bash
# Usage: task-create.sh <agent_name> <title> [description] [priority] [assignee] [status]
# priority: low|normal|high|urgent  status: inbox|todo|in_progress|review|done|failed|blocked
AGENT="${1:?Agent name required}"
TITLE="${2:?Task title required}"
DESC="${3:-}"
PRIORITY="${4:-normal}"
ASSIGNEE="${5:-}"
STATUS="${6:-inbox}"
BOARD_URL="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

PAYLOAD=$(python3 -c "
import json, sys
d = {'title': sys.argv[1], 'description': sys.argv[2], 'priority': sys.argv[3],
     'created_by': sys.argv[4], 'status': sys.argv[5]}
if sys.argv[6]: d['assignee'] = sys.argv[6]
print(json.dumps(d))
" "$TITLE" "$DESC" "$PRIORITY" "$AGENT" "$STATUS" "$ASSIGNEE")

curl -sf -X POST "$BOARD_URL/tasks" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | python3 -m json.tool --no-ensure-ascii
