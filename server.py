#!/usr/bin/env python3
"""Serve the UI and run provision/cleanup scripts when buttons are clicked."""

from __future__ import annotations

import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PORT = 5173
SCRIPTS = {
    "/api/create-instance": ROOT / "create_instance.py",
    "/api/cleanup-instance": ROOT / "cleanup_instance.py",
}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self) -> None:
        script = SCRIPTS.get(self.path.rstrip("/"))
        if script is None:
            self.send_error(404, "Not found")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()

        proc = subprocess.Popen(
            [sys.executable, str(script)],
            cwd=str(ROOT),
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
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Serving on http://127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.", flush=True)


if __name__ == "__main__":
    main()
