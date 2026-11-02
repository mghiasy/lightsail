#!/usr/bin/env bash
# Prefer a local Node 20 under .tools/, then nvm, then whatever `node` is on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_NODE="$(echo "$ROOT"/.tools/node-v20*/bin)"

if [[ -x "${LOCAL_NODE}/node" ]]; then
  export PATH="${LOCAL_NODE}:$PATH"
elif [[ -x /usr/local/opt/node@20/bin/node ]]; then
  export PATH="/usr/local/opt/node@20/bin:$PATH"
elif [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  nvm use 20 >/dev/null
fi

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
if [[ "$NODE_MAJOR" -lt 20 ]]; then
  cat <<EOF >&2
Playwright needs Node.js 20+. Current: $(node -v 2>/dev/null || echo 'not found')

Quick fix in this repo:
  export PATH="/usr/local/opt/node@20/bin:\$PATH"

Or install Node 20 system-wide (nvm / brew), then re-run.
EOF
  exit 1
fi

# Keep browsers outside ephemeral Cursor sandbox caches.
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$ROOT/.tools/playwright}"

exec "$@"
