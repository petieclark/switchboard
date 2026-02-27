#!/bin/bash
# Usage: heartbeat.sh <agent_name> [status]
# status: active|idle|blocked (default: active)
AGENT="${1:?Agent name required}"
STATUS="${2:-active}"
BOARD_URL="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

curl -sf -X POST "$BOARD_URL/agents/heartbeat" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$AGENT\",\"status\":\"$STATUS\"}" \
  && echo "" || echo "AgentBoard unreachable"
