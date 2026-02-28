"""
Switchboard — local coordination layer for OpenClaw agents
Self-hosted, zero internet dependency. Route your agents. Run your fleet.
"""

import sqlite3
import json
import time
import os
from datetime import datetime, timezone
from contextlib import contextmanager
from typing import Optional, List
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# ── Config ─────────────────────────────────────────────────────────────────────
_db_env = os.environ.get("SWITCHBOARD_DB")
DB_PATH = Path(_db_env) if _db_env else Path(__file__).parent / "data" / "switchboard.db"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
STATIC_DIR = Path(__file__).parent / "static"

app = FastAPI(title="Switchboard", version="2.0.0", docs_url="/api/docs")

# ── Priority ordering ──────────────────────────────────────────────────────────
PRIORITY_ORDER = {"urgent": 0, "high": 1, "normal": 2, "low": 3}

# ── DB Bootstrap ───────────────────────────────────────────────────────────────
SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    description TEXT    DEFAULT '',
    context     TEXT    DEFAULT '',
    output      TEXT    DEFAULT '',
    tags        TEXT    DEFAULT '[]',
    status      TEXT    NOT NULL DEFAULT 'inbox',
    priority    TEXT    NOT NULL DEFAULT 'normal',
    created_by  TEXT    NOT NULL DEFAULT 'unknown',
    assignee    TEXT    DEFAULT NULL,
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS agents (
    name           TEXT PRIMARY KEY,
    last_heartbeat TEXT NOT NULL,
    status         TEXT NOT NULL DEFAULT 'active',
    meta           TEXT DEFAULT '{}'
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
"""

MIGRATIONS = [
    "ALTER TABLE tasks ADD COLUMN context TEXT DEFAULT ''",
    "ALTER TABLE tasks ADD COLUMN output  TEXT DEFAULT ''",
    "ALTER TABLE tasks ADD COLUMN tags    TEXT DEFAULT '[]'",
]

def init_db():
    with sqlite3.connect(DB_PATH) as con:
        con.executescript(SCHEMA)
        # Run migrations safely (ignore if column already exists)
        for migration in MIGRATIONS:
            try:
                con.execute(migration)
                con.commit()
            except sqlite3.OperationalError:
                pass  # Column already exists

init_db()

@contextmanager
def get_db():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    try:
        yield con
        con.commit()
    finally:
        con.close()

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def row_to_dict(row):
    if row is None:
        return None
    d = dict(row)
    # Parse tags JSON
    if "tags" in d and isinstance(d["tags"], str):
        try:
            d["tags"] = json.loads(d["tags"])
        except Exception:
            d["tags"] = []
    return d

# ── Models ─────────────────────────────────────────────────────────────────────
VALID_STATUSES = {"inbox", "todo", "in_progress", "review", "done", "failed", "blocked"}
VALID_PRIORITIES = {"low", "normal", "high", "urgent"}

class TaskCreate(BaseModel):
    title: str
    description: Optional[str] = ""
    context: Optional[str] = ""
    tags: Optional[List[str]] = []
    status: Optional[str] = "inbox"
    priority: Optional[str] = "normal"
    created_by: Optional[str] = "unknown"
    assignee: Optional[str] = None

class TaskUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    context: Optional[str] = None
    output: Optional[str] = None
    tags: Optional[List[str]] = None
    status: Optional[str] = None
    priority: Optional[str] = None
    assignee: Optional[str] = None

class HeartbeatIn(BaseModel):
    name: str
    status: Optional[str] = "active"
    meta: Optional[dict] = {}

class MessageCreate(BaseModel):
    from_agent: str
    to_agent: Optional[str] = None
    task_id: Optional[int] = None
    content: str

# ── Health ─────────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"status": "ok", "ts": now_iso(), "version": "2.0.0"}

# ── Agents ─────────────────────────────────────────────────────────────────────
@app.post("/agents/heartbeat")
def heartbeat(body: HeartbeatIn):
    with get_db() as con:
        con.execute("""
            INSERT INTO agents(name, last_heartbeat, status, meta)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                last_heartbeat = excluded.last_heartbeat,
                status = excluded.status,
                meta = excluded.meta
        """, (body.name, now_iso(), body.status, json.dumps(body.meta or {})))
    return {"ok": True, "agent": body.name}

@app.get("/agents")
def list_agents():
    with get_db() as con:
        rows = con.execute("SELECT * FROM agents ORDER BY last_heartbeat DESC").fetchall()
    agents = [row_to_dict(r) for r in rows]
    cutoff = time.time() - 300
    for a in agents:
        ts = datetime.fromisoformat(a["last_heartbeat"]).timestamp()
        if ts < cutoff and a["status"] != "offline":
            a["status"] = "offline"
    return agents

# ── Tasks ──────────────────────────────────────────────────────────────────────
@app.post("/tasks", status_code=201)
def create_task(body: TaskCreate):
    if body.status not in VALID_STATUSES:
        raise HTTPException(400, f"Invalid status. Valid: {VALID_STATUSES}")
    if body.priority not in VALID_PRIORITIES:
        raise HTTPException(400, f"Invalid priority. Valid: {VALID_PRIORITIES}")
    ts = now_iso()
    tags_json = json.dumps(body.tags or [])
    with get_db() as con:
        cur = con.execute("""
            INSERT INTO tasks(title, description, context, output, tags, status, priority, created_by, assignee, created_at, updated_at)
            VALUES (?, ?, ?, '', ?, ?, ?, ?, ?, ?, ?)
        """, (body.title, body.description, body.context, tags_json,
              body.status, body.priority, body.created_by, body.assignee, ts, ts))
        task_id = cur.lastrowid
    return {"id": task_id, "title": body.title, "status": body.status}

@app.get("/tasks/queue")
def task_queue(agent: str = Query(..., description="Agent name to fetch work for")):
    """
    Return the next claimable task for an agent.
    Returns tasks in status=todo assigned to this agent (or unassigned),
    ordered by priority then age.
    """
    with get_db() as con:
        rows = con.execute("""
            SELECT * FROM tasks
            WHERE status = 'todo'
              AND (assignee = ? OR assignee IS NULL)
            ORDER BY created_at ASC
        """, (agent,)).fetchall()

    tasks = [row_to_dict(r) for r in rows]
    # Sort by priority order
    tasks.sort(key=lambda t: PRIORITY_ORDER.get(t.get("priority", "normal"), 2))
    return {"agent": agent, "queue": tasks, "count": len(tasks)}

@app.post("/tasks/{task_id}/claim")
def claim_task(task_id: int, agent: str = Query(..., description="Agent claiming this task")):
    """
    Atomically claim a task. Sets assignee + moves to in_progress.
    Returns 409 if task is already claimed/in_progress.
    """
    with get_db() as con:
        row = con.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Task not found")
        task = row_to_dict(row)

        if task["status"] == "in_progress":
            raise HTTPException(409, f"Task already in progress by {task.get('assignee', 'unknown')}")
        if task["status"] not in ("todo", "inbox"):
            raise HTTPException(409, f"Task cannot be claimed from status: {task['status']}")

        ts = now_iso()
        con.execute("""
            UPDATE tasks SET status = 'in_progress', assignee = ?, updated_at = ?
            WHERE id = ? AND status != 'in_progress'
        """, (agent, ts, task_id))
        updated = row_to_dict(con.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone())

    return updated

@app.get("/tasks")
def list_tasks(
    status: Optional[str] = None,
    assignee: Optional[str] = None,
    created_by: Optional[str] = None,
    tag: Optional[str] = None,
):
    query = "SELECT * FROM tasks WHERE 1=1"
    params = []
    if status:
        query += " AND status = ?"
        params.append(status)
    if assignee:
        query += " AND assignee = ?"
        params.append(assignee)
    if created_by:
        query += " AND created_by = ?"
        params.append(created_by)
    if tag:
        query += " AND tags LIKE ?"
        params.append(f'%"{tag}"%')
    query += " ORDER BY updated_at DESC"
    with get_db() as con:
        rows = con.execute(query, params).fetchall()
    return [row_to_dict(r) for r in rows]

@app.get("/tasks/{task_id}")
def get_task(task_id: int):
    with get_db() as con:
        row = con.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if not row:
        raise HTTPException(404, "Task not found")
    return row_to_dict(row)

@app.patch("/tasks/{task_id}")
def update_task(task_id: int, body: TaskUpdate):
    if body.status and body.status not in VALID_STATUSES:
        raise HTTPException(400, f"Invalid status. Valid: {VALID_STATUSES}")
    with get_db() as con:
        existing = con.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not existing:
            raise HTTPException(404, "Task not found")
        updates = {}
        for k, v in body.model_dump().items():
            if v is not None:
                if k == "tags":
                    updates[k] = json.dumps(v)
                else:
                    updates[k] = v
        if not updates:
            return row_to_dict(existing)
        updates["updated_at"] = now_iso()
        set_clause = ", ".join(f"{k} = ?" for k in updates)
        values = list(updates.values()) + [task_id]
        con.execute(f"UPDATE tasks SET {set_clause} WHERE id = ?", values)
        row = con.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    return row_to_dict(row)

@app.delete("/tasks/{task_id}")
def delete_task(task_id: int):
    with get_db() as con:
        row = con.execute("SELECT id FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Task not found")
        con.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
    return {"ok": True, "deleted": task_id}

# ── Messages ───────────────────────────────────────────────────────────────────
@app.post("/messages", status_code=201)
def send_message(body: MessageCreate):
    ts = now_iso()
    with get_db() as con:
        cur = con.execute("""
            INSERT INTO messages(from_agent, to_agent, task_id, content, created_at)
            VALUES (?, ?, ?, ?, ?)
        """, (body.from_agent, body.to_agent, body.task_id, body.content, ts))
        msg_id = cur.lastrowid
    return {"id": msg_id, "ok": True}

@app.get("/messages")
def list_messages(
    to_agent: Optional[str] = None,
    from_agent: Optional[str] = None,
    task_id: Optional[int] = None,
    unread_only: bool = False,
    limit: int = Query(50, le=200),
):
    query = "SELECT * FROM messages WHERE 1=1"
    params = []
    if to_agent:
        query += " AND to_agent = ?"
        params.append(to_agent)
    if from_agent:
        query += " AND from_agent = ?"
        params.append(from_agent)
    if task_id:
        query += " AND task_id = ?"
        params.append(task_id)
    if unread_only:
        query += " AND read = 0"
    query += " ORDER BY created_at DESC LIMIT ?"
    params.append(limit)
    with get_db() as con:
        rows = con.execute(query, params).fetchall()
    return [row_to_dict(r) for r in rows]

@app.patch("/messages/{msg_id}/read")
def mark_read(msg_id: int):
    with get_db() as con:
        con.execute("UPDATE messages SET read = 1 WHERE id = ?", (msg_id,))
    return {"ok": True}

# ── Board summary ──────────────────────────────────────────────────────────────
@app.get("/board")
def board_summary():
    with get_db() as con:
        tasks = [row_to_dict(r) for r in con.execute("SELECT * FROM tasks ORDER BY updated_at DESC").fetchall()]
        agents = [row_to_dict(r) for r in con.execute("SELECT * FROM agents ORDER BY last_heartbeat DESC").fetchall()]
        unread_count = con.execute("SELECT COUNT(*) FROM messages WHERE read = 0").fetchone()[0]
        queued_count = con.execute("SELECT COUNT(*) FROM tasks WHERE status = 'todo'").fetchone()[0]

    by_status = {}
    for t in tasks:
        s = t["status"]
        by_status.setdefault(s, []).append(t)

    return {
        "tasks": by_status,
        "agents": agents,
        "unread_messages": unread_count,
        "queued_tasks": queued_count,
        "totals": {s: len(v) for s, v in by_status.items()},
    }

# ── Dashboard HTML ─────────────────────────────────────────────────────────────
@app.get("/", response_class=HTMLResponse)
def dashboard():
    html_path = STATIC_DIR / "index.html"
    if html_path.exists():
        return HTMLResponse(html_path.read_text())
    return HTMLResponse("<p>Dashboard loading... refresh in a moment.</p>")
