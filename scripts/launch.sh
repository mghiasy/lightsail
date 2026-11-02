#!/usr/bin/env bash
# Start the Lightsail web UI (if needed) and open it in the browser.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=5173
URL="http://127.0.0.1:${PORT}"
PID_FILE="${ROOT}/.lightsail-server.pid"
LOG_FILE="${ROOT}/.lightsail-server.log"

is_up() {
  curl -sf --max-time 1 "${URL}/" >/dev/null 2>&1
}

start_server() {
  if ! command -v python3 >/dev/null 2>&1; then
    osascript -e 'display alert "Lightsail" message "python3 was not found. Install Python 3, then try again."' >/dev/null 2>&1 || true
    echo "error: python3 not found" >&2
    exit 1
  fi

  cd "$ROOT"
  nohup python3 backend/server.py >"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"

  for _ in $(seq 1 30); do
    if is_up; then
      return 0
    fi
    sleep 0.2
  done

  osascript -e "display alert \"Lightsail\" message \"Server failed to start. Check ${LOG_FILE}\"" >/dev/null 2>&1 || true
  echo "error: server did not become ready; see ${LOG_FILE}" >&2
  exit 1
}

if ! is_up; then
  start_server
fi

open "$URL"
echo "Lightsail is running at ${URL}"
echo "Stop later with: npm run stop   (or: kill \$(cat ${PID_FILE}))"
