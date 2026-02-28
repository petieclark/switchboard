#!/usr/bin/env bash
# task-output.sh — write agent output to a task and mark done/failed
# Usage: task-output.sh <task_id> <status> "<output_text>"
# status: done | failed | review
# Example: task-output.sh 42 done "Fixed the login bug. Updated auth middleware line 87."

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

TASK_ID="${1:?Usage: task-output.sh <task_id> <status> <output>}"
STATUS="${2:?status required (done|failed|review)}"
OUTPUT="${3:?output required}"

PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({'output': sys.argv[1], 'status': sys.argv[2]}))
" "$OUTPUT" "$STATUS")

curl -sf -X PATCH "$BASE/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
