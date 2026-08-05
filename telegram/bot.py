#!/usr/bin/env python3
"""Telegram bot that runs Lightsail create/cleanup scripts."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND_DIR = ROOT / "backend"
CREATE_SCRIPT = BACKEND_DIR / "create_instance.py"
CLEANUP_SCRIPT = BACKEND_DIR / "cleanup_instance.py"

API = "https://api.telegram.org/bot{token}/{method}"
TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
ALLOWED_RAW = os.environ.get("TELEGRAM_ALLOWED_USER_IDS", "").strip()
ALLOWED_IDS = {int(x) for x in ALLOWED_RAW.split(",") if x.strip().isdigit()}

BUSY_CHATS: set[int] = set()


def require_token() -> str:
    if not TOKEN:
        raise SystemExit(
            "Set TELEGRAM_BOT_TOKEN first, e.g.\n"
            '  export TELEGRAM_BOT_TOKEN="123456:ABC..."\n'
            "  npm run bot"
        )
    return TOKEN


def api(method: str, payload: dict | None = None) -> dict:
    token = require_token()
    url = API.format(token=token, method=method)
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Telegram API {method} failed: {exc.code} {detail}") from exc
    if not body.get("ok"):
        raise RuntimeError(f"Telegram API {method} error: {body}")
    return body["result"]


def send_message(chat_id: int, text: str, reply_markup: dict | None = None) -> int:
    payload: dict = {
        "chat_id": chat_id,
        "text": text[:4000],
        "disable_web_page_preview": True,
    }
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    result = api("sendMessage", payload)
    return int(result["message_id"])


def edit_message(chat_id: int, message_id: int, text: str) -> None:
    try:
        api(
            "editMessageText",
            {
                "chat_id": chat_id,
                "message_id": message_id,
                "text": text[:4000],
                "disable_web_page_preview": True,
            },
        )
    except RuntimeError as exc:
        # Ignore "message is not modified" style failures.
        if "not modified" not in str(exc).lower():
            print(f"editMessageText warning: {exc}", file=sys.stderr)


def answer_callback(callback_id: str, text: str = "") -> None:
    api(
        "answerCallbackQuery",
        {"callback_query_id": callback_id, "text": text[:200]},
    )


def main_keyboard() -> dict:
    return {
        "inline_keyboard": [
            [{"text": "Create cusor_instance", "callback_data": "create"}],
            [{"text": "Clean up", "callback_data": "cleanup"}],
        ]
    }


def allowed(user_id: int | None) -> bool:
    if not ALLOWED_IDS:
        return True
    return user_id is not None and user_id in ALLOWED_IDS


def run_script(script: Path, chat_id: int) -> tuple[int, str, str | None]:
    """Run backend script; stream progress into one Telegram message."""
    status_id = send_message(chat_id, "Starting…")
    lines: list[str] = []
    access_key: str | None = None
    last_edit = 0.0

    proc = subprocess.Popen(
        [sys.executable, str(script)],
        cwd=str(BACKEND_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proc.stdout is not None

    for raw in proc.stdout:
        line = raw.rstrip("\n")
        if not line:
            continue
        if line.startswith("ss://") or line.startswith("ssconf://"):
            access_key = line
        try:
            payload = json.loads(line)
            if isinstance(payload, dict) and payload.get("accessKey"):
                access_key = str(payload["accessKey"])
            if isinstance(payload, dict) and payload.get("notFound"):
                lines.append(payload.get("error") or "Instance does not exist.")
        except json.JSONDecodeError:
            pass

        if line.startswith("PROGRESS|"):
            parts = line.split("|", 2)
            msg = parts[2] if len(parts) > 2 else line
            lines.append(f"• {msg}")
        elif line.startswith("ERROR:") or line.startswith("FAILED"):
            lines.append(line)

        now = time.time()
        if now - last_edit >= 1.5:
            edit_message(chat_id, status_id, "Progress:\n" + "\n".join(lines[-20:]))
            last_edit = now

    code = proc.wait()
    summary = "Progress:\n" + ("\n".join(lines[-20:]) if lines else "No output.")
    if code == 0:
        if access_key:
            summary += f"\n\nAccess key:\n{access_key}"
        else:
            summary += "\n\nDone."
    else:
        summary += f"\n\nFAILED (exit {code})"
    edit_message(chat_id, status_id, summary)
    return code, summary, access_key


def handle_update(update: dict) -> None:
    if "callback_query" in update:
        cb = update["callback_query"]
        data = cb.get("data")
        cb_id = cb["id"]
        user = cb.get("from") or {}
        user_id = user.get("id")
        message = cb.get("message") or {}
        chat = message.get("chat") or {}
        chat_id = chat.get("id")
        if chat_id is None:
            return

        if not allowed(user_id):
            answer_callback(cb_id, "Not authorized")
            send_message(chat_id, "You are not authorized to use this bot.")
            return

        if chat_id in BUSY_CHATS:
            answer_callback(cb_id, "Already running")
            send_message(chat_id, "A job is already running. Please wait.")
            return

        if data == "create":
            answer_callback(cb_id, "Creating…")
            BUSY_CHATS.add(chat_id)
            try:
                run_script(CREATE_SCRIPT, chat_id)
            finally:
                BUSY_CHATS.discard(chat_id)
            send_message(chat_id, "Choose an action:", reply_markup=main_keyboard())
            return

        if data == "cleanup":
            answer_callback(cb_id, "Cleaning up…")
            BUSY_CHATS.add(chat_id)
            try:
                run_script(CLEANUP_SCRIPT, chat_id)
            finally:
                BUSY_CHATS.discard(chat_id)
            send_message(chat_id, "Choose an action:", reply_markup=main_keyboard())
            return

        answer_callback(cb_id)
        return

    message = update.get("message") or {}
    text = (message.get("text") or "").strip()
    chat = message.get("chat") or {}
    chat_id = chat.get("id")
    user = message.get("from") or {}
    user_id = user.get("id")
    if chat_id is None:
        return

    if not allowed(user_id):
        send_message(chat_id, "You are not authorized to use this bot.")
        return

    if text.startswith("/start") or text.startswith("/menu"):
        send_message(
            chat_id,
            "Lightsail bot\n\nCreate Ubuntu 24 + Outline, or clean up the instance.",
            reply_markup=main_keyboard(),
        )
        return

    if text.startswith("/whoami"):
        send_message(chat_id, f"Your Telegram user id: {user_id}")
        return

    send_message(
        chat_id,
        "Use the buttons below, or /start",
        reply_markup=main_keyboard(),
    )


def main() -> None:
    require_token()
    print("Telegram bot starting…", flush=True)
    if ALLOWED_IDS:
        print(f"Allowlist enabled: {sorted(ALLOWED_IDS)}", flush=True)
    else:
        print(
            "WARNING: TELEGRAM_ALLOWED_USER_IDS is unset — anyone who finds the bot can run it.",
            flush=True,
        )

    me = api("getMe")
    print(f"Logged in as @{me.get('username')} ({me.get('id')})", flush=True)

    offset = 0
    while True:
        try:
            updates = api(
                "getUpdates",
                {"timeout": 50, "offset": offset, "allowed_updates": ["message", "callback_query"]},
            )
        except Exception as exc:  # noqa: BLE001
            print(f"getUpdates error: {exc}", file=sys.stderr, flush=True)
            time.sleep(3)
            continue

        for update in updates:
            offset = max(offset, int(update["update_id"]) + 1)
            try:
                handle_update(update)
            except Exception as exc:  # noqa: BLE001
                print(f"update error: {exc}", file=sys.stderr, flush=True)
                chat = (
                    (update.get("callback_query") or {}).get("message")
                    or update.get("message")
                    or {}
                ).get("chat") or {}
                chat_id = chat.get("id")
                if chat_id is not None:
                    send_message(chat_id, f"Error: {exc}")


if __name__ == "__main__":
    main()
