#!/usr/bin/env bash
# task-review.sh — submit QA review result for a task
# Usage: task-review.sh <task_id> <pass|fail> "<review_notes>" [iteration_if_fail]
#
# pass → marks task done (or keeps in review if QA1 already passed, for QA2)
# fail → appends notes to review_notes, increments iteration, moves back to todo

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"
TASK_ID="${1:?Usage: task-review.sh <task_id> <pass|fail> <notes>}"
RESULT="${2:?result required: pass|fail}"
NOTES="${3:?notes required}"

if [[ "$RESULT" == "pass" ]]; then
  # Check if QA1 already passed (detect from current review_notes)
  CURRENT=$(curl -sf "$BASE/tasks/$TASK_ID" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('review_notes',''))")
  if echo "$CURRENT" | grep -q "QA1:PASS"; then
    # Second pass — mark done
    NEW_NOTES="${CURRENT}
QA2:PASS — ${NOTES}"
    PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'status':'done','review_notes':sys.argv[1]}))" "$NEW_NOTES")
  else
    # First pass — mark QA1 pass, keep in review for QA2
    NEW_NOTES="QA1:PASS — ${NOTES}"
    PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'review_notes':sys.argv[1]}))" "$NEW_NOTES")
  fi
else
  # Fail — append notes, increment iteration, back to todo
  CURRENT_DATA=$(curl -sf "$BASE/tasks/$TASK_ID")
  CURRENT_NOTES=$(echo "$CURRENT_DATA" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('review_notes',''))")
  CURRENT_ITER=$(echo "$CURRENT_DATA" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('iteration',0))")
  NEW_ITER=$((CURRENT_ITER + 1))
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  NEW_NOTES="${CURRENT_NOTES}
❌ REVIEW FAIL [iter ${NEW_ITER}, ${TIMESTAMP}]: ${NOTES}"
  PAYLOAD=$(python3 -c "
import json,sys
print(json.dumps({
  'status': 'todo',
  'review_notes': sys.argv[1],
  'iteration': int(sys.argv[2]),
  'output': ''
}))
" "$NEW_NOTES" "$NEW_ITER")
fi

curl -sf -X PATCH "$BASE/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
