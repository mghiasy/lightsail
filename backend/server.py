#!/usr/bin/env python3
"""Serve the web UI and run provision/cleanup scripts when buttons are clicked."""

from __future__ import annotations

import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

from app_paths import backend_dir, web_dir, worker_command

BACKEND_DIR = backend_dir()
WEB_DIR = web_dir()
PORT = 5173
API_ACTIONS = {
    "/api/create-instance": "create-instance",
    "/api/cleanup-instance": "cleanup-instance",
}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.end_headers()

    def do_POST(self) -> None:
        action = API_ACTIONS.get(self.path.rstrip("/"))
        if action is None:
            self.send_error(404, "Not found")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()

        proc = subprocess.Popen(
            worker_command(action),
            cwd=str(BACKEND_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            self.wfile.write(line.encode("utf-8"))
            self.wfile.flush()
        code = proc.wait()
        if code != 0:
            self.wfile.write(f"\nFAILED (exit {code})\n".encode("utf-8"))
            self.wfile.flush()

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))


def main() -> None:
    if not WEB_DIR.is_dir():
        raise SystemExit(f"Web directory not found: {WEB_DIR}")

    # 0.0.0.0 so iOS Simulator/devices on LAN can reach the API (web still works locally).
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Serving on http://127.0.0.1:{PORT}", flush=True)
    print(f"LAN:     http://<your-mac-ip>:{PORT}", flush=True)
    print(f"Web:     {WEB_DIR}", flush=True)
    print(f"Backend: {BACKEND_DIR}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.", flush=True)


if __name__ == "__main__":
    main()
