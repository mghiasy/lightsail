#!/usr/bin/env bash
# Build the fully standalone Flutter iOS app (UI + on-device provisioning).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/flutter/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

if [[ ! -d /Applications/Xcode.app ]]; then
  cat <<'EOF'
Xcode is required to build an iPhone app.

1. Install Xcode from the Mac App Store
2. Open Xcode once, accept the license, wait for extra components
3. Run:
     sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
     sudo xcodebuild -runFirstLaunch
4. Re-run this script:
     bash scripts/build-ios-standalone.sh
EOF
  exit 1
fi

sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer >/dev/null
xcodebuild -runFirstLaunch >/dev/null 2>&1 || true

if ! command -v pod >/dev/null 2>&1; then
  echo "Installing CocoaPods…"
  if command -v brew >/dev/null 2>&1; then
    brew install cocoapods
  else
    sudo gem install cocoapods
  fi
fi

cd "${ROOT}/mobile"
flutter pub get
cd ios
pod install --repo-update
cd ..

echo "Building iOS release…"
flutter build ios --release --no-codesign

echo
echo "Built unsigned Runner.app at:"
echo "  ${ROOT}/mobile/build/ios/iphoneos/Runner.app"
echo
echo "To install on your iPhone:"
echo "  1. open ${ROOT}/mobile/ios/Runner.xcworkspace"
echo "  2. Select your Team under Signing & Capabilities"
echo "  3. Plug in your iPhone → Product → Run"
echo "  or Product → Archive for an IPA / TestFlight"
