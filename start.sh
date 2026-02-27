#!/bin/bash
cd "$(dirname "$0")"
exec .venv/bin/uvicorn app:app --host 127.0.0.1 --port 19400 --log-level info
