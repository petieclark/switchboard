FROM python:3.12-slim

LABEL org.opencontainers.image.title="Switchboard"
LABEL org.opencontainers.image.description="Local coordination layer for OpenClaw agents"
LABEL org.opencontainers.image.source="https://github.com/yourusername/switchboard"

WORKDIR /app

# Install deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY app.py .
COPY static/ static/

# Data volume
RUN mkdir -p /data
ENV SWITCHBOARD_DB=/data/switchboard.db

EXPOSE 19400

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "19400", "--log-level", "info"]
