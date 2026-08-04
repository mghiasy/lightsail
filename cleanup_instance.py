#!/usr/bin/env python3
"""Stop and delete the Lightsail instance, then release its static IP."""

from __future__ import annotations

import json
import subprocess
import sys
import time

REGION = "us-west-2"
INSTANCE_NAME = "cusor_instance"
STATIC_IP_NAME = "cusor_instance-ip"


def progress(step: str, message: str) -> None:
    print(f"PROGRESS|{step}|{message}", flush=True)


def aws(*args: str) -> dict:
    cmd = ["aws", "lightsail", *args, "--region", REGION, "--output", "json"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "AWS CLI command failed").strip()
        raise RuntimeError(detail)
    if not result.stdout.strip():
        return {}
    return json.loads(result.stdout)


def aws_ok(*args: str) -> tuple[bool, str, dict]:
    cmd = ["aws", "lightsail", *args, "--region", REGION, "--output", "json"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return False, (result.stderr or result.stdout or "").strip(), {}
    payload = json.loads(result.stdout) if result.stdout.strip() else {}
    return True, "", payload


def get_instance_state() -> str | None:
    ok, _, data = aws_ok("get-instance", "--instance-name", INSTANCE_NAME)
    if not ok:
        return None
    return data["instance"]["state"]["name"]


def stop_instance() -> None:
    state = get_instance_state()
    if state is None:
        progress("stop", f"Instance {INSTANCE_NAME} not found — skipping stop")
        progress("stopped", "Instance stopped")
        return

    if state in {"stopped", "stopping"}:
        progress("stop", f"Instance already {state}")
    else:
        progress("stop", f"Stopping instance {INSTANCE_NAME}…")
        aws("stop-instance", "--instance-name", INSTANCE_NAME)

    progress("stop", "Waiting until instance is stopped…")
    while True:
        state = get_instance_state()
        if state is None:
            progress("stopped", "Instance no longer exists")
            return
        progress("stop", f"Instance state: {state}")
        if state == "stopped":
            progress("stopped", "Instance stopped")
            return
        if state in {"terminated", "terminating"}:
            progress("stopped", f"Instance {state}")
            return
        time.sleep(5)


def delete_instance() -> None:
    state = get_instance_state()
    if state is None:
        progress("delete_instance", f"Instance {INSTANCE_NAME} already gone")
        progress("instance_deleted", "Instance deleted")
        return

    progress("delete_instance", f"Deleting instance {INSTANCE_NAME}…")
    aws("delete-instance", "--instance-name", INSTANCE_NAME)

    progress("delete_instance", "Waiting until instance is gone…")
    while True:
        state = get_instance_state()
        if state is None:
            progress("instance_deleted", "Instance deleted")
            return
        progress("delete_instance", f"Instance state: {state}")
        time.sleep(5)


def delete_static_ip() -> None:
    ok, _, data = aws_ok("get-static-ip", "--static-ip-name", STATIC_IP_NAME)
    if not ok:
        progress("delete_ip", f"Static IP {STATIC_IP_NAME} already gone")
        progress("ip_deleted", "Static IP deleted")
        return

    attached = data.get("staticIp", {}).get("attachedTo")
    if attached:
        progress("delete_ip", f"Detaching static IP from {attached}…")
        try:
            aws(
                "detach-static-ip",
                "--static-ip-name",
                STATIC_IP_NAME,
            )
        except RuntimeError as exc:
            if "not attached" not in str(exc).lower():
                raise

    progress("delete_ip", f"Deleting static IP {STATIC_IP_NAME}…")
    aws("release-static-ip", "--static-ip-name", STATIC_IP_NAME)
    progress("ip_deleted", "Static IP deleted")


def fail(message: str) -> int:
    short = " ".join(message.split())
    if len(short) > 240:
        short = short[:240] + "…"
    progress("error", short)
    print(json.dumps({"ok": False, "error": message}), flush=True)
    print(f"ERROR: {message}", file=sys.stderr, flush=True)
    return 1


def main() -> int:
    try:
        if get_instance_state() is None:
            message = f"Instance {INSTANCE_NAME} does not exist."
            print(
                json.dumps(
                    {
                        "ok": False,
                        "notFound": True,
                        "error": message,
                        "instance": INSTANCE_NAME,
                    }
                ),
                flush=True,
            )
            return 0

        stop_instance()
        delete_instance()
        delete_static_ip()
        progress("done", "Cleanup complete")
        print(
            json.dumps(
                {
                    "ok": True,
                    "cleaned": True,
                    "instance": INSTANCE_NAME,
                    "staticIp": STATIC_IP_NAME,
                }
            ),
            flush=True,
        )
        return 0
    except Exception as exc:  # noqa: BLE001
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main())
