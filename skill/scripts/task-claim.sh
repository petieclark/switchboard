#!/usr/bin/env bash
# task-claim.sh — atomically claim a task (set assignee + move to in_progress)
# Usage: task-claim.sh <agent_name> <task_id>
# Returns 409 if already claimed

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"
AGENT="${1:?Usage: task-claim.sh <agent_name> <task_id>}"
TASK_ID="${2:?task_id required}"

curl -sf -X POST "$BASE/tasks/$TASK_ID/claim?agent=$AGENT"
