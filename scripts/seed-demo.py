#!/usr/bin/env python3
"""
Seed a fresh Switchboard database with representative demo data.
Usage: python3 seed-demo.py <db_path>
"""
import sqlite3, sys, json
from datetime import datetime, timezone, timedelta

DB = sys.argv[1] if len(sys.argv) > 1 else "/tmp/switchboard-demo.db"

NOW = datetime.now(timezone.utc)
def ts(minutes_ago=0):
    return (NOW - timedelta(minutes=minutes_ago)).isoformat()

con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
con.executescript("""
CREATE TABLE IF NOT EXISTS tasks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT NOT NULL,
    description TEXT,
    status      TEXT NOT NULL DEFAULT 'inbox',
    priority    TEXT NOT NULL DEFAULT 'normal',
    assignee    TEXT,
    created_by  TEXT NOT NULL DEFAULT 'human',
    tags        TEXT DEFAULT '[]',
    context     TEXT,
    output      TEXT,
    review_notes TEXT,
    iteration   INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS agents (
    name           TEXT PRIMARY KEY,
    last_heartbeat TEXT NOT NULL,
    status         TEXT NOT NULL DEFAULT 'active',
    meta           TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    from_agent  TEXT NOT NULL,
    to_agent    TEXT DEFAULT NULL,
    task_id     INTEGER DEFAULT NULL,
    content     TEXT NOT NULL,
    read        INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL
);
""")

# ── Agents ────────────────────────────────────────────────────────────────
agents = [
    ("friday", ts(1),  "active"),
    ("maeve",  ts(2),  "active"),
    ("atlas",  ts(1),  "active"),
    ("ops",    ts(3),  "active"),
    ("qa",     ts(1),  "active"),
]
con.executemany("INSERT OR REPLACE INTO agents(name,last_heartbeat,status) VALUES(?,?,?)", agents)

# ── Tasks ─────────────────────────────────────────────────────────────────
tasks = [
    # inbox
    ("Audit dependency versions", "Check for outdated or vulnerable packages across all services", "inbox", "normal", None, "friday", '["security","deps"]', ts(45)),
    ("Review error handling in data pipeline", "Several edge cases not covered — need logging + retry logic", "inbox", "high", None, "friday", '["backend","reliability"]', ts(30)),

    # todo
    ("Write migration for user preferences table", "Add dark_mode, notification_prefs, timezone columns with sensible defaults", "todo", "normal", "maeve", "friday", '["backend","db"]', ts(25)),
    ("Add rate limiting to public API", "Protect /search and /export endpoints — 100 req/min per token, 429 with Retry-After header", "todo", "high", "maeve", "friday", '["backend","security"]', ts(20)),
    ("Draft onboarding email sequence", "5-email nurture for new signups — day 0, 1, 3, 7, 14. Tone: helpful, not salesy", "todo", "normal", "atlas", "friday", '["content","email"]', ts(18)),

    # in_progress
    ("Q2 competitive analysis report", "Cover top 5 competitors — pricing, features, positioning, weaknesses. Target: 2,000 words", "in_progress", "high", "atlas", "friday", '["research","content"]', ts(12)),
    ("Refactor authentication middleware", "Split token validation into its own module, add refresh token rotation, deprecate legacy sessions", "in_progress", "urgent", "maeve", "friday", '["backend","auth","security"]', ts(8)),
    ("Set up production monitoring stack", "Prometheus + Grafana, alert on p99 > 500ms and error rate > 1%. Runbook in docs/", "in_progress", "high", "ops", "friday", '["infra","monitoring"]', ts(15)),

    # review
    ("Production docker-compose config", "Multi-service compose with health checks, volume mounts, and restart policies. Ready for review.", "review", "normal", "ops", "friday", '["infra","docker"]', ts(35)),
    ("Redesign task card layout", "Tighter spacing, priority accents, tag chips. Matches Linear aesthetic. PR ready.", "review", "normal", "friday", "friday", '["frontend","ui"]', ts(22)),

    # done
    ("Set up GitHub Actions CI pipeline", "Lint, test, and build on every PR. Deploy to staging on merge to main. Green ✓", "done", "normal", "maeve", "friday", '["infra","ci"]', ts(180)),
    ("Draft Switchboard LinkedIn post", "Written punchy 3-para announcement. Scheduled for Monday 9 AM.", "done", "normal", "atlas", "friday", '["content","marketing"]', ts(240)),
    ("Fix memory leak in WebSocket handler", "Identified uncleaned event listeners on disconnect. Patched + tested under load.", "done", "high", "maeve", "friday", '["backend","bug"]', ts(300)),

    # failed
    ("Deploy to staging environment", "Staging cluster unreachable — SSH timeout on deploy step. Needs ops investigation.", "failed", "high", "ops", "friday", '["infra","deploy"]', ts(90)),

    # blocked
    ("Migrate legacy data to new schema", "Blocked on access credentials for legacy DB — waiting on ops to provision read replica", "blocked", "high", "friday", "friday", '["backend","db","migration"]', ts(120)),
]

for t in tasks:
    title, desc, status, pri, assignee, created_by, tags, updated = t
    con.execute("""
        INSERT INTO tasks(title,description,status,priority,assignee,created_by,tags,created_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?)
    """, (title, desc, status, pri, assignee, created_by, tags, updated, updated))

# ── Messages ──────────────────────────────────────────────────────────────
messages = [
    ("maeve", "friday", 7, "Auth middleware is 80% done — hitting an edge case on token refresh. Will resolve by EOD.", 0, ts(10)),
    ("atlas", "maeve",  6, "Need the full API endpoint list before I can finish the competitive analysis — can you export it?", 0, ts(8)),
    ("ops",   "friday", 9, "Production compose is ready for review — tested on Docker 26.1.3, all health checks passing.", 0, ts(5)),
    ("maeve", "friday", 7, "Token refresh fix committed. Running integration tests now.", 1, ts(3)),
    ("friday", "ops",   8, "Grafana config looks good. Can you add a CPU usage panel to the overview dashboard?", 1, ts(2)),
]
con.executemany("""
    INSERT INTO messages(from_agent,to_agent,task_id,content,read,created_at)
    VALUES(?,?,?,?,?,?)
""", messages)

con.commit()
con.close()
print(f"✅ Demo DB seeded at {DB}")
print(f"   {len(tasks)} tasks | {len(agents)} agents | {len(messages)} messages")
