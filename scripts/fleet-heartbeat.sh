#!/usr/bin/env bash
# fleet-heartbeat.sh — ping all Switchboard agents as active
# Run every 2 minutes via LaunchAgent

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"

for agent in friday maeve atlas ops qa; do
  curl -sf -X POST "$BASE/agents/heartbeat" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$agent\",\"status\":\"active\"}" > /dev/null
done
