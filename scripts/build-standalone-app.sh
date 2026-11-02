#!/usr/bin/env bash
# Build a standalone macOS Lightsail.app into dist/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PYTHON="${PYTHON:-python3}"
VENV="${ROOT}/.venv-app"

echo "==> Creating build virtualenv at ${VENV}"
"${PYTHON}" -m venv "${VENV}"
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

echo "==> Installing build dependencies"
pip install --upgrade pip wheel
pip install "pyinstaller>=6.3" "awscli>=1.32"

echo "==> Building Lightsail.app (this can take a few minutes)"
rm -rf build dist/Lightsail dist/Lightsail.app
pyinstaller --noconfirm --clean "${ROOT}/macos/Lightsail.spec"

APP="${ROOT}/dist/Lightsail.app"
if [[ ! -d "${APP}" ]]; then
  echo "error: expected ${APP} was not created" >&2
  exit 1
fi

# Clear quarantine so Gatekeeper is less likely to block a local build.
xattr -dr com.apple.quarantine "${APP}" 2>/dev/null || true

echo
echo "Built: ${APP}"
echo "Run:   open \"${APP}\""
echo
echo "Still required on this Mac:"
echo "  - AWS credentials (aws configure, or env vars)"
echo "  - Outline Manager (optional; API fallback works without UI automation)"
echo "  - ssh (built into macOS)"
