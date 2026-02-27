#!/bin/bash
# Usage: task-claim.sh <agent_name> <task_id>
# Assigns the task to this agent and moves it to in_progress
AGENT="${1:?Agent name required}"
TASK_ID="${2:?Task ID required}"
BOARD_URL="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

curl -sf -X PATCH "$BOARD_URL/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d "{\"assignee\":\"$AGENT\",\"status\":\"in_progress\"}" | python3 -m json.tool --no-ensure-ascii
