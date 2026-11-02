"""Resolve resource paths for both source runs and the packaged macOS app."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path


def is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"))


def meipass() -> Path:
    return Path(getattr(sys, "_MEIPASS"))


def backend_dir() -> Path:
    if is_frozen():
        return meipass() / "backend"
    return Path(__file__).resolve().parent


def web_dir() -> Path:
    if is_frozen():
        return meipass() / "web"
    return Path(__file__).resolve().parent.parent / "web"


def applescript_path() -> Path:
    return backend_dir() / "open_outline_manager.applescript"


def aws_command(*lightsail_args: str) -> list[str]:
    """
    Build an AWS Lightsail CLI invocation.

    Prefers a system `aws` binary. In the packaged app, falls back to the
    embedded awscli module via the same executable (`--aws-cli ...`).
    """
    region = os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
    tail = ["lightsail", *lightsail_args, "--region", region, "--output", "json"]

    system_aws = shutil.which("aws")
    if system_aws and not is_frozen():
        return [system_aws, *tail]

    if system_aws:
        # Packaged app can still use a user-installed AWS CLI if present.
        return [system_aws, *tail]

    if is_frozen():
        return [sys.executable, "--aws-cli", *tail]

    # Dev fallback: awscli installed in the active Python env.
    return [sys.executable, "-m", "awscli", *tail]


def worker_command(action: str) -> list[str]:
    """
    Command to run create/cleanup as a child process.

    action: 'create-instance' | 'cleanup-instance'
    """
    if is_frozen():
        return [sys.executable, f"--{action}"]
    script = backend_dir() / f"{action.replace('-', '_')}.py"
    return [sys.executable, str(script)]
