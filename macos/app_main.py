#!/usr/bin/env python3
"""
Standalone Lightsail macOS app entrypoint.

Modes:
  (default)              Start local web UI and open the browser
  --create-instance      Provision worker (used by the web UI)
  --cleanup-instance     Cleanup worker (used by the web UI)
  --aws-cli ...          Embedded AWS CLI (when system `aws` is missing)
"""

from __future__ import annotations

import os
import sys
import threading
import time
import traceback
import urllib.request
import webbrowser
from pathlib import Path

# Allow importing backend modules when running from source.
_ROOT = Path(__file__).resolve().parent.parent
_BACKEND = _ROOT / "backend"
if _BACKEND.is_dir() and str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))


def _log_path() -> Path:
    base = Path.home() / "Library" / "Logs"
    base.mkdir(parents=True, exist_ok=True)
    return base / "Lightsail.log"


def _setup_logging() -> None:
    if not getattr(sys, "frozen", False):
        return
    log = open(_log_path(), "a", encoding="utf-8", buffering=1)
    sys.stdout = log  # type: ignore[assignment]
    sys.stderr = log  # type: ignore[assignment]
    print(f"\n--- Lightsail start {time.strftime('%Y-%m-%d %H:%M:%S')} ---", flush=True)


def _run_aws_cli(argv: list[str]) -> int:
    sys.argv = ["aws", *argv]
    try:
        from awscli.clidriver import main as aws_main
    except ImportError:
        print(
            "AWS CLI is not available. Install it with:\n  brew install awscli\n"
            "or rebuild the app with awscli bundled.",
            file=sys.stderr,
        )
        return 1
    return int(aws_main())


def _server_is_up(url: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=0.4) as resp:
            return 200 <= getattr(resp, "status", 200) < 500
    except Exception:
        return False


def _open_browser_when_ready(url: str, attempts: int = 50) -> None:
    for _ in range(attempts):
        if _server_is_up(url):
            webbrowser.open(url)
            return
        time.sleep(0.15)
    webbrowser.open(url)


def _alert(message: str) -> None:
    try:
        import subprocess

        subprocess.run(
            [
                "osascript",
                "-e",
                f'display alert "Lightsail" message {message!r}',
            ],
            check=False,
            capture_output=True,
        )
    except Exception:
        print(message, file=sys.stderr)


def _serve() -> int:
    import server

    url = f"http://127.0.0.1:{server.PORT}/"

    # Already running from a previous launch — just focus the UI.
    if _server_is_up(url):
        webbrowser.open(url)
        return 0

    threading.Thread(target=_open_browser_when_ready, args=(url,), daemon=True).start()
    try:
        server.main()
    except OSError as exc:
        # Port busy or bind failure.
        if _server_is_up(url):
            webbrowser.open(url)
            return 0
        _alert(f"Could not start the Lightsail server.\n\n{exc}\n\nSee {_log_path()}")
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    _setup_logging()

    try:
        if argv[:1] == ["--create-instance"]:
            from create_instance import main as create_main

            return int(create_main())

        if argv[:1] == ["--cleanup-instance"]:
            from cleanup_instance import main as cleanup_main

            return int(cleanup_main())

        if argv[:1] == ["--aws-cli"]:
            return _run_aws_cli(argv[1:])

        os.environ.setdefault("LIGHTSAIL_STANDALONE", "1")
        return _serve()
    except Exception:
        traceback.print_exc()
        if getattr(sys, "frozen", False) and argv[:1] not in (
            ["--create-instance"],
            ["--cleanup-instance"],
            ["--aws-cli"],
        ):
            _alert(f"Lightsail crashed.\n\nSee log:\n{_log_path()}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
