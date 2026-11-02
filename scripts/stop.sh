#!/usr/bin/env bash
# Stop the background Lightsail web server started by launch.sh / Lightsail.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=5173
PID_FILE="${ROOT}/.lightsail-server.pid"

stop_pid() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 0.3
    kill -9 "$pid" 2>/dev/null || true
    echo "Stopped Lightsail server (pid ${pid})"
    return 0
  fi
  return 1
}

stopped=false
if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && stop_pid "$pid"; then
    stopped=true
  fi
  rm -f "$PID_FILE"
fi

# Fallback: anything listening on the app port that looks like our server.
if ! $stopped; then
  pids="$(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "${pids}" ]]; then
    for pid in $pids; do
      stop_pid "$pid" || true
    done
    stopped=true
  fi
fi

if ! $stopped; then
  echo "Lightsail server is not running."
fi
