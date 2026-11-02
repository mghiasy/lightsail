#!/usr/bin/env bash
# Double-click in Finder: prefer the standalone app if built, else source launcher.
cd "$(dirname "$0")"

if [[ -d dist/Lightsail.app ]]; then
  open dist/Lightsail.app
  exit 0
fi

echo "Standalone app not built yet."
echo "Building it now (first time takes a few minutes)…"
bash scripts/build-standalone-app.sh
open dist/Lightsail.app
