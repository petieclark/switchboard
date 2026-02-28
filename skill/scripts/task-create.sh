#!/usr/bin/env bash
# task-create.sh — create a task on Switchboard
# Usage: task-create.sh <agent> "<title>" "<desc>" [priority] [assignee] [status] [context] [tags_csv]
# Example: task-create.sh friday "Fix login bug" "Users can't login" high maeve todo "Check auth middleware in app.py" "debug,backend"

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

AGENT="${1:?Usage: task-create.sh <agent> <title> [desc] [priority] [assignee] [status] [context] [tags_csv]}"
TITLE="${2:?title required}"
DESC="${3:-}"
PRIORITY="${4:-normal}"
ASSIGNEE="${5:-}"
STATUS="${6:-todo}"
CONTEXT="${7:-}"
TAGS_CSV="${8:-}"

# Build tags array
TAGS_JSON="[]"
if [[ -n "$TAGS_CSV" ]]; then
  TAGS_JSON=$(echo "$TAGS_CSV" | python3 -c "import sys,json; t=sys.stdin.read().strip().split(','); print(json.dumps([x.strip() for x in t if x.strip()]))")
fi

PAYLOAD=$(python3 -c "
import json, sys
d = {
  'title': sys.argv[1],
  'description': sys.argv[2],
  'context': sys.argv[3],
  'tags': json.loads(sys.argv[4]),
  'status': sys.argv[5],
  'priority': sys.argv[6],
  'created_by': sys.argv[7],
}
if sys.argv[8]: d['assignee'] = sys.argv[8]
print(json.dumps(d))
" "$TITLE" "$DESC" "$CONTEXT" "$TAGS_JSON" "$STATUS" "$PRIORITY" "$AGENT" "$ASSIGNEE")

curl -sf -X POST "$BASE/tasks" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
