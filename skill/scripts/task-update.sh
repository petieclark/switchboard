#!/bin/bash
# Usage: task-update.sh <task_id> <field> <value>
# Fields: status | assignee | priority | title | description
# Status values: inbox|todo|in_progress|review|done|failed|blocked
TASK_ID="${1:?Task ID required}"
FIELD="${2:?Field required}"
VALUE="${3:?Value required}"
BOARD_URL="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({sys.argv[1]:sys.argv[2]}))" "$FIELD" "$VALUE")

curl -sf -X PATCH "$BOARD_URL/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | python3 -m json.tool --no-ensure-ascii
