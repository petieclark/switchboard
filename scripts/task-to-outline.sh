#!/usr/bin/env bash
# task-to-outline.sh — publish a completed Switchboard task to Outline
# Format mirrors a PR: overview, context/brief, changes made, output/deliverable
#
# Usage: task-to-outline.sh <task_id>
#
# Publishes to the "Switchboard Output" collection.

set -euo pipefail

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"
OUTLINE_BASE="https://notes.petieclark.com"
OUTLINE_KEY="ol_api_nirDDDHG7pi6jD08P9xdAVy7c3ygzqsDsdzPXH"
COLLECTION_ID="5d0f7695-d7b7-49f6-a914-82dd9e9aafc5"  # Switchboard Output

TASK_ID="${1:?Usage: task-to-outline.sh <task_id>}"

# ── Fetch task ────────────────────────────────────────────────────────────────
TASK=$(curl -sf "$BASE/tasks/$TASK_ID")
if [[ -z "$TASK" ]]; then
  echo "ERROR: Task $TASK_ID not found" >&2
  exit 1
fi

TITLE=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t['title'])")
STATUS=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t['status'])")
PRIORITY=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('priority','normal'))")
ASSIGNEE=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('assignee') or 'unknown')")
CONTEXT=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('context',''))")
OUTPUT=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('output',''))")
REVIEW_NOTES=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('review_notes',''))")
ITERATION=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('iteration',0))")
TAGS=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); tags=t.get('tags',[]); print(', '.join(tags) if tags else 'none')")
CREATED_AT=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('created_at','')[:10])")
UPDATED_AT=$(echo "$TASK" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t.get('updated_at','')[:16].replace('T',' '))")

# ── Detect task type from tags ────────────────────────────────────────────────
IS_CODE=false
IS_CONTENT=false
IS_RESEARCH=false

echo "$TAGS" | grep -qiE "ios|swift|maeve|code|fix|bug|css|js|python|go|docker|infra|ops|cleanup|deploy" && IS_CODE=true
echo "$TAGS" | grep -qiE "linkedin|blog|writing|post|content|copy|draft" && IS_CONTENT=true
echo "$TAGS" | grep -qiE "research|atlas|analysis|investigate|report" && IS_RESEARCH=true

# ── Priority badge ─────────────────────────────────────────────────────────────
case "$PRIORITY" in
  critical) PRIORITY_BADGE="🔴 critical" ;;
  high)     PRIORITY_BADGE="🟠 high" ;;
  normal)   PRIORITY_BADGE="🟡 normal" ;;
  low)      PRIORITY_BADGE="🟢 low" ;;
  *)        PRIORITY_BADGE="$PRIORITY" ;;
esac

# ── Agent badge ────────────────────────────────────────────────────────────────
case "$ASSIGNEE" in
  maeve)  AGENT_EMOJI="⚙️ maeve" ;;
  atlas)  AGENT_EMOJI="🔍 atlas" ;;
  ops)    AGENT_EMOJI="🛠️ ops" ;;
  friday) AGENT_EMOJI="🎯 friday" ;;
  qa)     AGENT_EMOJI="✅ qa" ;;
  *)      AGENT_EMOJI="🤖 $ASSIGNEE" ;;
esac

# ── Iteration note ─────────────────────────────────────────────────────────────
ITER_NOTE=""
if [[ "$ITERATION" -gt 0 ]]; then
  ITER_NOTE="↩ Returned to worker $ITERATION time(s) by QA before passing"
fi

# ── Build document ─────────────────────────────────────────────────────────────
DOC=$(python3 - <<PYEOF
import sys

title = """$TITLE"""
task_id = "$TASK_ID"
status = "$STATUS"
priority_badge = """$PRIORITY_BADGE"""
agent_emoji = """$AGENT_EMOJI"""
created_at = "$CREATED_AT"
updated_at = "$UPDATED_AT"
tags = """$TAGS"""
iter_note = """$ITER_NOTE"""
review_notes = """$REVIEW_NOTES"""
context = """$CONTEXT"""
output = """$OUTPUT"""
is_code = $IS_CODE
is_content = $IS_CONTENT
is_research = $IS_RESEARCH

lines = []

# ── Header ────────────────────────────────────────────────────────────────────
lines.append(f"# {title}")
lines.append("")
lines.append("| | |")
lines.append("|---|---|")
lines.append(f"| **Task** | #{task_id} |")
lines.append(f"| **Status** | ✅ done |")
lines.append(f"| **Priority** | {priority_badge} |")
lines.append(f"| **Agent** | {agent_emoji} |")
lines.append(f"| **Tags** | \`{tags}\` |")
lines.append(f"| **Completed** | {updated_at} UTC |")
if iter_note:
    lines.append(f"| **Revisions** | {iter_note} |")
lines.append("")
lines.append("---")
lines.append("")

# ── Brief / Context ────────────────────────────────────────────────────────────
lines.append("## Brief")
lines.append("")
lines.append("> *What the agent was asked to do*")
lines.append("")
if context:
    lines.append(context)
else:
    lines.append("*(no context provided)*")
lines.append("")
lines.append("---")
lines.append("")

# ── Output section — format depends on task type ───────────────────────────────
if is_code:
    lines.append("## Changes")
    lines.append("")
    lines.append("> *Files modified, commands run, verification results*")
    lines.append("")
elif is_content:
    lines.append("## Deliverable")
    lines.append("")
    lines.append("> *Final content produced*")
    lines.append("")
elif is_research:
    lines.append("## Findings")
    lines.append("")
    lines.append("> *Research results, analysis, and recommendations*")
    lines.append("")
else:
    lines.append("## Output")
    lines.append("")

if output:
    lines.append(output)
else:
    lines.append("*(no output recorded)*")
lines.append("")
lines.append("---")
lines.append("")

# ── QA Review ──────────────────────────────────────────────────────────────────
lines.append("## QA Review")
lines.append("")
if review_notes:
    # Split QA1 and QA2 passes for clarity
    for line in review_notes.split("\\n"):
        line = line.strip()
        if not line:
            continue
        if line.startswith("QA1:PASS"):
            lines.append(f"✅ **QA1 Pass** — {line.replace('QA1:PASS — ','')}")
        elif line.startswith("QA2:PASS"):
            lines.append(f"✅ **QA2 Pass** — {line.replace('QA2:PASS — ','')}")
        elif line.startswith("❌"):
            lines.append(f"🔄 **Returned** — {line}")
        else:
            lines.append(line)
else:
    lines.append("*(no review notes)*")
lines.append("")

print("\\n".join(lines))
PYEOF
)

# ── Publish to Outline ─────────────────────────────────────────────────────────
DOC_TITLE="[#${TASK_ID}] ${TITLE}"

PAYLOAD=$(python3 -c "
import json, sys
title = sys.argv[1]
text = sys.argv[2]
collection = sys.argv[3]
print(json.dumps({
  'title': title,
  'text': text,
  'collectionId': collection,
  'publish': True
}))
" "$DOC_TITLE" "$DOC" "$COLLECTION_ID")

RESPONSE=$(curl -sf -X POST "$OUTLINE_BASE/api/documents.create" \
  -H "Authorization: Bearer $OUTLINE_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

DOC_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['id'])" 2>/dev/null || echo "")
DOC_URL=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['url'])" 2>/dev/null || echo "")

if [[ -n "$DOC_ID" ]]; then
  echo "✅ Published to Outline: $DOC_URL"
  # Patch outline_url onto the task (store in output suffix)
  curl -sf -X PATCH "$BASE/tasks/$TASK_ID" \
    -H "Content-Type: application/json" \
    -d "{\"review_notes\": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$REVIEW_NOTES
📎 Outline: $DOC_URL")}" > /dev/null
else
  echo "ERROR: Outline publish failed" >&2
  echo "$RESPONSE" >&2
  exit 1
fi
