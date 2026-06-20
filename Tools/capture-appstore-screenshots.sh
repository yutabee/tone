#!/usr/bin/env bash
# Capture App Store screenshots (6.9" iPhone) in dark + light, in-tune + sharp,
# using the DEBUG demo pitch engine so no microphone is needed.
# Output: fastlane/screenshots/en-US/  (deliver matches by image size).
#
# Usage: bash Tools/capture-appstore-screenshots.sh
set -euo pipefail

DEVICE="${SIM_DEVICE:-iPhone 17 Pro Max}"   # 6.9" class (1320×2868)
BUNDLE_ID="jp.syncbloom.tone"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/fastlane/screenshots/en-US"
DD="$ROOT/build/dd"
mkdir -p "$OUT"

cd "$ROOT"
[ -d "Tone.xcodeproj" ] || xcodegen generate

echo "▶ building for simulator…"
xcodebuild -project Tone.xcodeproj -scheme Tone -configuration Debug \
  -sdk iphonesimulator -derivedDataPath "$DD" \
  -destination "platform=iOS Simulator,name=$DEVICE" build >/dev/null
APP="$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'Tone.app' | head -1)"
[ -n "$APP" ] || { echo "Tone.app not found"; exit 1; }

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"

shoot() { # <appearance> <hz> <name>
  xcrun simctl ui "$DEVICE" appearance "$1"
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" --tone-demo "--tone-demo-hz=$2" >/dev/null
  sleep 3   # let the cents EMA settle
  xcrun simctl io "$DEVICE" screenshot "$OUT/$3.png"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
}

shoot dark  440 "01-in-tune-dark"
shoot dark  448 "02-sharp-dark"
shoot light 440 "03-in-tune-light"
shoot light 448 "04-sharp-light"

echo "✓ wrote screenshots to $OUT"
ls -1 "$OUT"
