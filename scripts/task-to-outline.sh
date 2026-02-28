#!/usr/bin/env bash
# task-to-outline.sh — publish a completed Switchboard task to Outline
# PR-style format: overview table, brief/context, changes/deliverable, QA review
#
# Usage: task-to-outline.sh <task_id>
# Publishes to the "Switchboard Output" collection.

set -euo pipefail

BASE="${SWITCHBOARD_URL:-http://127.0.0.1:19400}"
OUTLINE_BASE="https://notes.petieclark.com"
OUTLINE_KEY="ol_api_nirDDDHG7pi6jD08P9xdAVy7c3ygzqsDsdzPXH"
COLLECTION_ID="5d0f7695-d7b7-49f6-a914-82dd9e9aafc5"  # Switchboard Output

TASK_ID="${1:?Usage: task-to-outline.sh <task_id>}"

# ── Fetch task JSON ────────────────────────────────────────────────────────────
TASK_JSON=$(curl -sf "$BASE/tasks/$TASK_ID")
if [[ -z "$TASK_JSON" ]]; then
  echo "ERROR: Task $TASK_ID not found" >&2
  exit 1
fi

# ── Build doc + publish, all in Python (avoids shell escaping hell) ────────────
python3 - "$TASK_JSON" "$TASK_ID" "$OUTLINE_BASE" "$OUTLINE_KEY" "$COLLECTION_ID" "$BASE" <<'PYEOF'
import sys, json, re, urllib.request, urllib.error

task      = json.loads(sys.argv[1])
task_id   = sys.argv[2]
outline   = sys.argv[3]
key       = sys.argv[4]
coll_id   = sys.argv[5]
api_base  = sys.argv[6]

title        = task.get("title", "")
status       = task.get("status", "done")
priority     = task.get("priority", "normal")
assignee     = task.get("assignee") or "unknown"
context      = task.get("context") or ""
output       = task.get("output") or ""
review_notes = task.get("review_notes") or ""
iteration    = task.get("iteration", 0)
tags         = task.get("tags") or []
created_at   = (task.get("created_at") or "")[:10]
updated_at   = (task.get("updated_at") or "")[:16].replace("T", " ")

tags_str = ", ".join(tags) if tags else "none"
tags_lower = tags_str.lower()

# ── Detect type from tags ──────────────────────────────────────────────────────
is_code     = bool(re.search(r'ios|swift|maeve|code|fix|bug|css|js|python|go|docker|infra|ops|cleanup|deploy', tags_lower))
is_content  = bool(re.search(r'linkedin|blog|writing|post|content|copy|draft', tags_lower))
is_research = bool(re.search(r'research|atlas|analysis|investigate|report|push', tags_lower))

# ── Badges ─────────────────────────────────────────────────────────────────────
priority_badges = {"critical": "🔴 critical", "high": "🟠 high", "normal": "🟡 normal", "low": "🟢 low"}
agent_emojis    = {"maeve": "⚙️ maeve", "atlas": "🔍 atlas", "ops": "🛠️ ops", "friday": "🎯 friday", "qa": "✅ qa"}
priority_badge  = priority_badges.get(priority, priority)
agent_badge     = agent_emojis.get(assignee, f"🤖 {assignee}")

# ── Build markdown ─────────────────────────────────────────────────────────────
lines = []

lines.append(f"# {title}")
lines.append("")
lines.append("| | |")
lines.append("|---|---|")
lines.append(f"| **Task** | #{task_id} |")
lines.append(f"| **Status** | ✅ done |")
lines.append(f"| **Priority** | {priority_badge} |")
lines.append(f"| **Agent** | {agent_badge} |")
lines.append(f"| **Tags** | `{tags_str}` |")
lines.append(f"| **Completed** | {updated_at} UTC |")
if iteration > 0:
    lines.append(f"| **Revisions** | ↩ Returned to worker {iteration}x before passing |")
lines.append("")
lines.append("---")
lines.append("")

# ── Brief ──────────────────────────────────────────────────────────────────────
lines.append("## Brief")
lines.append("")
lines.append("> *What the agent was asked to do*")
lines.append("")
lines.append(context if context else "*(no context provided)*")
lines.append("")
lines.append("---")
lines.append("")

# ── Output section (type-aware heading) ───────────────────────────────────────
if is_content:
    lines.append("## Deliverable")
    lines.append("")
    lines.append("> *Final content produced*")
elif is_research:
    lines.append("## Findings")
    lines.append("")
    lines.append("> *Research results, analysis, and recommendations*")
elif is_code:
    lines.append("## Changes")
    lines.append("")
    lines.append("> *Files modified, commands run, verification results*")
else:
    lines.append("## Output")
    lines.append("")
lines.append("")
lines.append(output if output else "*(no output recorded)*")
lines.append("")
lines.append("---")
lines.append("")

# ── QA Review ──────────────────────────────────────────────────────────────────
lines.append("## QA Review")
lines.append("")
if review_notes:
    for line in review_notes.split("\n"):
        line = line.strip()
        if not line or line.startswith("📎 Outline:"):
            continue
        if line.startswith("QA1:PASS"):
            lines.append(f"✅ **QA1 Pass** — {line.replace('QA1:PASS — ', '').replace('QA1:PASS', '')}")
        elif line.startswith("QA2:PASS"):
            lines.append(f"✅ **QA2 Pass** — {line.replace('QA2:PASS — ', '').replace('QA2:PASS', '')}")
        elif line.startswith("❌"):
            lines.append(f"🔄 **Returned** — {line}")
        else:
            lines.append(line)
else:
    lines.append("*(no review notes)*")
lines.append("")

doc_md = "\n".join(lines)
doc_title = f"[#{task_id}] {title}"

# ── Publish to Outline ─────────────────────────────────────────────────────────
payload = json.dumps({
    "title": doc_title,
    "text": doc_md,
    "collectionId": coll_id,
    "publish": True
}).encode("utf-8")

req = urllib.request.Request(
    f"{outline}/api/documents.create",
    data=payload,
    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    method="POST"
)
try:
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
    doc_url = result["data"]["url"]
    doc_id  = result["data"]["id"]
    print(f"✅ Published: {doc_url}")

    # Patch Outline URL into review_notes
    new_notes = review_notes.rstrip() + f"\n📎 Outline: {doc_url}"
    patch = json.dumps({"review_notes": new_notes}).encode("utf-8")
    patch_req = urllib.request.Request(
        f"{api_base}/tasks/{task_id}",
        data=patch,
        headers={"Content-Type": "application/json"},
        method="PATCH"
    )
    with urllib.request.urlopen(patch_req):
        pass
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print(f"ERROR: Outline publish failed ({e.code}): {body}", file=sys.stderr)
    sys.exit(1)
PYEOF
