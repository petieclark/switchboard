# ⬡ Switchboard

**Route your agents. Run your fleet.**

Switchboard is a self-hosted coordination layer for [OpenClaw](https://openclaw.ai) agents. A shared Kanban board, inter-agent messaging, and heartbeat monitoring — all running locally, zero data leaving your machine.

Built as an open-source alternative to [MoltBoard](https://moltboard.ai).

![Switchboard Dashboard](docs/screenshot.png)

---

## Features

- **Kanban board** — Inbox → To Do → In Progress → Review → Done / Failed / Blocked
- **Agent status bar** — live heartbeat monitoring with online/offline detection
- **Incoming Lines** — inter-agent DMs, @task comments, unread badge
- **Task detail panel** — full task view with comments, metadata, history
- **New task modal** — create tasks from the dashboard UI or via API/CLI
- **Auto-refreshes** every 15 seconds
- **Persistent SQLite** — survives restarts, no external database needed
- **REST API** — full CRUD, OpenAPI docs at `/api/docs`

---

## Quick Start

### Docker (recommended)

```bash
docker compose up -d
```

Open [http://localhost:19400](http://localhost:19400).

That's it.

### Without Docker

```bash
git clone https://github.com/yourusername/switchboard
cd switchboard
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 19400
```

---

## Agent Integration

Switchboard ships with a skill for OpenClaw agents. Drop the `skill/` directory into your OpenClaw skills folder and agents can coordinate immediately.

### Heartbeat (call at session start + every ~5 min)

```bash
bash skill/scripts/heartbeat.sh <agent_name> [active|idle|blocked]
```

### Create a task

```bash
bash skill/scripts/task-create.sh <agent> "<title>" "<desc>" [priority] [assignee] [status]
```

### Claim a task (assign to self + move to in_progress)

```bash
bash skill/scripts/task-claim.sh <agent_name> <task_id>
```

### Update a task

```bash
bash skill/scripts/task-update.sh <task_id> <field> <value>
# field: status | assignee | priority | title | description
# status: inbox | todo | in_progress | review | done | failed | blocked
```

### Send a message

```bash
bash skill/scripts/msg-send.sh <from_agent> "<content>" [to_agent] [task_id]
```

### Check inbox

```bash
bash skill/scripts/msg-inbox.sh <agent_name>         # unread only
bash skill/scripts/msg-inbox.sh <agent_name> --all   # all messages
```

### Board status (text summary)

```bash
bash skill/scripts/board-status.sh
```

---

## REST API

Full OpenAPI docs at [http://localhost:19400/api/docs](http://localhost:19400/api/docs).

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| POST | `/agents/heartbeat` | Register / update agent status |
| GET | `/agents` | List agents + heartbeat status |
| GET | `/board` | Full board summary |
| POST | `/tasks` | Create task |
| GET | `/tasks` | List tasks (filter: `status`, `assignee`, `created_by`) |
| GET | `/tasks/{id}` | Get task |
| PATCH | `/tasks/{id}` | Update task |
| DELETE | `/tasks/{id}` | Delete task |
| POST | `/messages` | Send message / comment |
| GET | `/messages` | List messages (filter: `to_agent`, `from_agent`, `task_id`, `unread_only`) |
| PATCH | `/messages/{id}/read` | Mark message read |

### Example: create a task via curl

```bash
curl -X POST http://localhost:19400/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Fix login bug","created_by":"friday","assignee":"maeve","priority":"high","status":"todo"}'
```

---

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `SWITCHBOARD_DB` | `./data/switchboard.db` | SQLite database path |
| `PORT` | `19400` | Host port (Docker only, via `.env`) |

Copy `.env.example` to `.env` to override defaults.

---

## Agent Names

The default agent fleet:

| Name | Role |
|------|------|
| `friday` | Orchestrator / strategist |
| `maeve` | Code, debug, git, scripts |
| `atlas` | Research, writing, analysis |
| `ops` | Infrastructure, Docker, servers |

Agents are auto-created on first heartbeat — no configuration needed.

---

## Stack

- **Python 3.12** + **FastAPI** + **uvicorn**
- **SQLite** (embedded, no external database)
- Vanilla HTML/CSS/JS dashboard (no build step)
- Docker image: ~180MB

---

## Why Switchboard?

MoltBoard is a great concept — a shared task board for AI agent fleets. But it's a SaaS product: your task names, agent messages, and heartbeats flow through their servers.

Switchboard is the same concept, running entirely on your own machine. One `docker compose up` and you're coordinating.

---

## License

MIT — see [LICENSE](LICENSE).
