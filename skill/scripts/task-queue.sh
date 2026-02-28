#!/usr/bin/env bash
# task-queue.sh — check next claimable task for an agent
# Usage: task-queue.sh <agent_name>
# Returns: JSON with queue array ordered by priority

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"
AGENT="${1:?Usage: task-queue.sh <agent_name>}"

curl -sf "$BASE/tasks/queue?agent=$AGENT"
