#!/usr/bin/env python3
"""Provision a Lightsail Ubuntu 24 instance and install Outline via AWS CLI + SSH."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REGION = "us-west-2"
AVAILABILITY_ZONE = "us-west-2a"
INSTANCE_NAME = "cusor_instance"
STATIC_IP_NAME = "cusor_instance-ip"
BLUEPRINT_ID = "ubuntu_24_04"
BUNDLE_ID = "small_3_0"  # ~$12/month
OUTLINE_INSTALL_URL = (
    "https://raw.githubusercontent.com/Jigsaw-Code/outline-server/"
    "master/src/server_manager/install_scripts/install_server.sh"
)
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
OUTLINE_JSON_RE = re.compile(
    r'\{\s*"apiUrl"\s*:\s*"[^"]+"\s*,\s*"certSha256"\s*:\s*"[^"]+"\s*\}'
)


def progress(step: str, message: str) -> None:
    """Emit a parseable progress line for the UI popup."""
    print(f"PROGRESS|{step}|{message}", flush=True)


def log(message: str) -> None:
    print(message, flush=True)


def aws(*args: str) -> dict:
    cmd = ["aws", "lightsail", *args, "--region", REGION, "--output", "json"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "AWS CLI command failed").strip()
        raise RuntimeError(detail)
    if not result.stdout.strip():
        return {}
    return json.loads(result.stdout)


def instance_exists() -> bool:
    result = subprocess.run(
        [
            "aws",
            "lightsail",
            "get-instance",
            "--instance-name",
            INSTANCE_NAME,
            "--region",
            REGION,
            "--output",
            "json",
        ],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def create_instance() -> None:
    if instance_exists():
        progress("create", f"Instance {INSTANCE_NAME} already exists — skipping create")
        progress("created", "Instance created")
        return

    progress("create", f"Creating instance {INSTANCE_NAME}…")
    aws(
        "create-instances",
        "--instance-names",
        INSTANCE_NAME,
        "--availability-zone",
        AVAILABILITY_ZONE,
        "--blueprint-id",
        BLUEPRINT_ID,
        "--bundle-id",
        BUNDLE_ID,
    )
    progress("created", "Instance created")


def wait_until_running() -> None:
    progress("waiting", "Waiting until instance is running…")
    while True:
        data = aws("get-instance", "--instance-name", INSTANCE_NAME)
        state = data["instance"]["state"]["name"]
        progress("waiting", f"Instance state: {state}")
        if state == "running":
            progress("running", "Instance running")
            return
        if state in {"stopped", "stopping", "terminated", "terminating", "error"}:
            raise RuntimeError(f"Instance entered unexpected state: {state}")
        time.sleep(5)


def get_static_ip_if_exists() -> dict | None:
    result = subprocess.run(
        [
            "aws",
            "lightsail",
            "get-static-ip",
            "--static-ip-name",
            STATIC_IP_NAME,
            "--region",
            REGION,
            "--output",
            "json",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout).get("staticIp")


def allocate_and_attach_static_ip() -> str:
    existing = get_static_ip_if_exists()
    if existing:
        progress("ip_create", f"Static IP {STATIC_IP_NAME} already exists — skipping allocate")
        progress("ip_created", "Static IP created")
    else:
        progress("ip_create", f"Creating static IP {STATIC_IP_NAME}…")
        aws("allocate-static-ip", "--static-ip-name", STATIC_IP_NAME)
        progress("ip_created", "Static IP created")
        existing = get_static_ip_if_exists() or {}

    progress("ip_attach", f"Attaching static IP to {INSTANCE_NAME}…")
    if existing.get("attachedTo") == INSTANCE_NAME:
        progress("ip_attached", "Static IP already attached")
    else:
        aws(
            "attach-static-ip",
            "--static-ip-name",
            STATIC_IP_NAME,
            "--instance-name",
            INSTANCE_NAME,
        )
        progress("ip_attached", "Static IP attached")

    data = aws("get-static-ip", "--static-ip-name", STATIC_IP_NAME)
    return data["staticIp"]["ipAddress"]


def get_default_private_key() -> str:
    """Lightsail instances use the account default key pair for SSH."""
    data = aws("download-default-key-pair")
    pem = data.get("privateKeyBase64") or data.get("privateKey") or ""
    if not pem.startswith("-----BEGIN"):
        raise RuntimeError("Could not download Lightsail default SSH key pair")
    return pem if pem.endswith("\n") else pem + "\n"


def write_temp_key(private_key: str) -> str:
    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        handle.write(private_key)
        key_path = handle.name
    os.chmod(key_path, 0o600)
    return key_path


def run_ssh(
    host: str,
    username: str,
    private_key: str,
    remote_command: str,
    timeout: int = 900,
    connect_timeout: int = 10,
) -> str:
    key_path: str | None = None
    try:
        key_path = write_temp_key(private_key)
        cmd = [
            "ssh",
            "-i",
            key_path,
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            f"ConnectTimeout={connect_timeout}",
            "-o",
            "ServerAliveInterval=30",
            f"{username}@{host}",
            remote_command,
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = (result.stdout or "") + (result.stderr or "")
        if result.returncode != 0:
            raise RuntimeError(output.strip() or f"SSH command failed ({result.returncode})")
        return result.stdout
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"SSH timed out after {timeout}s") from exc
    finally:
        if key_path:
            Path(key_path).unlink(missing_ok=True)


def wait_for_ssh(public_ip: str, timeout: int = 180) -> dict:
    """Probe SSH with the default key. Do not wait for cloud-init (very slow)."""
    progress("ssh", f"Waiting for SSH on {public_ip}…")
    private_key = get_default_private_key()
    username = "ubuntu"
    deadline = time.time() + timeout
    last_error = "timed out"
    attempt = 0
    while time.time() < deadline:
        attempt += 1
        try:
            # Quick readiness probe only — previously we blocked on cloud-init --wait.
            run_ssh(
                public_ip,
                username,
                private_key,
                "echo ready",
                timeout=20,
                connect_timeout=8,
            )
            progress("ssh", f"SSH ready ({username}@{public_ip})")
            return {
                "ipAddress": public_ip,
                "username": username,
                "privateKey": private_key,
            }
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc).strip().splitlines()[-1] if str(exc).strip() else str(exc)
            remaining = max(0, int(deadline - time.time()))
            progress(
                "ssh",
                f"SSH not ready (attempt {attempt}, {remaining}s left): {last_error}",
            )
            time.sleep(5)
    raise RuntimeError(f"SSH not ready after {timeout}s: {last_error}")


def install_outline(access: dict, public_ip: str) -> str:
    progress("outline", "Installing Docker (if needed) and Outline…")
    remote = f"""
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# cloud-init may still hold the apt lock after SSH is up
for i in $(seq 1 60); do
  if sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
    echo "Waiting for apt lock… ($i)"
    sleep 5
  else
    break
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker…"
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo systemctl enable --now docker

# Avoid interactive replace prompts on re-runs
sudo docker rm -f shadowbox watchtower >/dev/null 2>&1 || true

wget -qO /tmp/install_server.sh '{OUTLINE_INSTALL_URL}'
sudo bash /tmp/install_server.sh --hostname '{public_ip}'

echo '---ACCESS_TXT---'
sudo cat /opt/outline/access.txt
echo '---SERVER_CONFIG---'
sudo cat /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null || true
"""
    key_path: str | None = None
    try:
        key_path = write_temp_key(access["privateKey"])
        cmd = [
            "ssh",
            "-i",
            key_path,
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "ConnectTimeout=15",
            "-o",
            "ServerAliveInterval=30",
            f"{access['username']}@{access['ipAddress']}",
            "bash -s",
        ]
        result = subprocess.run(
            cmd,
            input=remote,
            capture_output=True,
            text=True,
            timeout=1200,
        )
        output = (result.stdout or "") + "\n" + (result.stderr or "")
        cleaned = ANSI_RE.sub("", output)
        if "---ACCESS_TXT---" not in cleaned:
            raise RuntimeError(cleaned.strip() or "Outline install failed")
        progress("outline", "Outline install finished")
        return cleaned
    finally:
        if key_path:
            Path(key_path).unlink(missing_ok=True)


def parse_outline_output(output: str, public_ip: str) -> dict:
    access_txt = ""
    if "---ACCESS_TXT---" in output:
        access_txt = output.split("---ACCESS_TXT---", 1)[1]
        if "---SERVER_CONFIG---" in access_txt:
            access_txt = access_txt.split("---SERVER_CONFIG---", 1)[0]

    api_url = None
    cert_sha = None
    for line in access_txt.splitlines():
        line = line.strip()
        if line.startswith("apiUrl:"):
            api_url = line.split("apiUrl:", 1)[1].strip()
        elif line.startswith("certSha256:"):
            cert_sha = line.split("certSha256:", 1)[1].strip()

    if not api_url or not cert_sha:
        match = OUTLINE_JSON_RE.search(output)
        if not match:
            raise RuntimeError("Could not find Outline apiUrl/certSha256 in install output")
        payload = json.loads(match.group(0))
        api_url = payload["apiUrl"]
        cert_sha = payload["certSha256"]

    management_port = None
    api_match = re.search(r":(\d+)/", api_url)
    if api_match:
        management_port = int(api_match.group(1))

    mgmt_msg = re.search(r"Management port\s+(\d+)", output, re.IGNORECASE)
    if mgmt_msg:
        management_port = int(mgmt_msg.group(1))

    keys_port = None
    keys_msg = re.search(r"Access key port\s+(\d+)", output, re.IGNORECASE)
    if keys_msg:
        keys_port = int(keys_msg.group(1))

    if keys_port is None and "---SERVER_CONFIG---" in output:
        config_blob = output.split("---SERVER_CONFIG---", 1)[1].strip()
        try:
            config = json.loads(config_blob.splitlines()[0])
            keys_port = int(config.get("portForNewAccessKeys"))
        except (json.JSONDecodeError, TypeError, ValueError, IndexError):
            pass

    if management_port is None or keys_port is None:
        raise RuntimeError(
            f"Could not parse required ports (management={management_port}, keys={keys_port})"
        )

    outline = {"apiUrl": api_url, "certSha256": cert_sha}
    return {
        "outline": outline,
        "managementPort": management_port,
        "accessKeyPort": keys_port,
        "publicIp": public_ip,
    }


def open_firewall_ports(management_port: int, access_key_port: int) -> None:
    progress(
        "firewall",
        f"Opening ports TCP {management_port}, TCP/UDP {access_key_port}…",
    )
    specs = [
        (management_port, management_port, "tcp"),
        (access_key_port, access_key_port, "tcp"),
        (access_key_port, access_key_port, "udp"),
    ]
    for from_port, to_port, protocol in specs:
        aws(
            "open-instance-public-ports",
            "--instance-name",
            INSTANCE_NAME,
            "--port-info",
            f"fromPort={from_port},toPort={to_port},protocol={protocol},cidrs=0.0.0.0/0",
        )
    progress("firewall", "Lightsail firewall ports opened")


def copy_to_clipboard(text: str) -> None:
    result = subprocess.run(["pbcopy"], input=text, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "pbcopy failed")


def read_clipboard() -> str:
    result = subprocess.run(["pbpaste"], capture_output=True, text=True)
    if result.returncode != 0:
        return ""
    return (result.stdout or "").strip()


def fetch_access_key_via_api(outline: dict) -> str | None:
    """Fetch Key 0 accessUrl from Outline Management API (reliable fallback)."""
    api_url = outline.get("apiUrl", "").rstrip("/")
    if not api_url:
        return None
    url = f"{api_url}/access-keys"
    result = subprocess.run(
        ["curl", "-sk", "--max-time", "20", url],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    keys = payload.get("accessKeys") or []
    if not keys:
        return None
    # Prefer the first key (install script creates Key 0 / first user).
    for key in keys:
        access_url = key.get("accessUrl") or key.get("access_url")
        if access_url:
            return access_url
    return None


def looks_like_access_key(value: str) -> bool:
    value = (value or "").strip()
    return value.startswith("ss://") or value.startswith("ssconf://")


def open_outline_manager_and_get_access_key(outline: dict) -> str | None:
    """
    Paste JSON into Outline Manager, click Done, copy Key 0 access key.
    Falls back to Management API. Never fails the run.
    """
    payload = json.dumps(outline, separators=(",", ":"))
    access_key: str | None = None
    try:
        progress("outline_manager", "Copying Outline JSON to clipboard…")
        copy_to_clipboard(payload)

        progress("outline_manager", "Opening / focusing Outline Manager…")
        launch = subprocess.run(
            ["open", "-a", "Outline Manager"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if launch.returncode != 0:
            progress(
                "outline_manager",
                "Could not open Outline Manager; will fetch access key via API. "
                f"({(launch.stderr or launch.stdout or 'open failed').strip()})",
            )
        else:
            script_path = Path(__file__).resolve().parent / "open_outline_manager.applescript"
            progress(
                "access_key",
                "Paste JSON → Done → share Key 0 → Copy access key…",
            )
            try:
                result = subprocess.run(
                    ["osascript", str(script_path), payload],
                    capture_output=True,
                    text=True,
                    timeout=45,
                )
                candidate = (result.stdout or "").strip()
                if not looks_like_access_key(candidate):
                    candidate = read_clipboard()
                if looks_like_access_key(candidate):
                    access_key = candidate
                    progress("access_key", "Access key copied from Outline Manager")
                elif result.returncode != 0:
                    detail = (result.stderr or result.stdout or "UI automation failed").strip()
                    progress(
                        "access_key",
                        "Manager UI copy unavailable — trying API. "
                        f"({detail.splitlines()[-1] if detail else 'automation failed'})",
                    )
                else:
                    progress("access_key", "Manager UI did not yield ss:// key — trying API…")
            except subprocess.TimeoutExpired:
                progress(
                    "access_key",
                    "Manager UI timed out — fetching access key via API…",
                )

        if not access_key:
            progress("access_key", "Fetching access key from Outline API…")
            access_key = fetch_access_key_via_api(outline)
            if access_key:
                copy_to_clipboard(access_key)
                progress("access_key", "Access key fetched from Outline API")
            else:
                progress(
                    "access_key",
                    "Could not get access key automatically. "
                    "In Outline Manager: Key 0 → share → Copy access key.",
                )
    except Exception as exc:  # noqa: BLE001 - never fail provision on Manager step
        progress(
            "access_key",
            f"Access-key step hit an error ({exc}); trying API fallback…",
        )
        try:
            access_key = fetch_access_key_via_api(outline)
        except Exception:  # noqa: BLE001
            access_key = None

    return access_key


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
        create_instance()
        wait_until_running()
        public_ip = allocate_and_attach_static_ip()

        access = wait_for_ssh(public_ip)

        install_output = install_outline(access, public_ip)
        parsed = parse_outline_output(install_output, public_ip)
        open_firewall_ports(parsed["managementPort"], parsed["accessKeyPort"])

        final_json = parsed["outline"]
        access_key = open_outline_manager_and_get_access_key(final_json)

        if not access_key:
            return fail("Could not get Outline access key")

        progress("done", "Outline access key ready")
        print(access_key, flush=True)
        print(
            json.dumps(
                {
                    "ok": True,
                    "accessKey": access_key,
                }
            ),
            flush=True,
        )
        return 0
    except Exception as exc:  # noqa: BLE001 - surface CLI errors to the UI
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main())
