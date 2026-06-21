#!/usr/bin/env bash
# Capture App Store screenshots (6.9" iPhone) in dark + light, in-tune + sharp,
# using the DEBUG demo pitch engine so no microphone is needed.
# Output: fastlane/screenshots/en-US/  (deliver matches by image size).
#
# Usage: bash Tools/capture-appstore-screenshots.sh
set -euo pipefail

DEVICE="${SIM_DEVICE:-iPhone 17 Pro Max}"   # 6.9" class (1320×2868)
BUNDLE_ID="com.yutabee.tone"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/fastlane/screenshots/en-US"
DD="$ROOT/build/dd"
mkdir -p "$OUT"
rm -f "$OUT"/*.png   # clear stale shots so renamed/removed entries don't linger

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

fork_shoot() { # <name>
  # --terminate-running-process so the new launch args (FORK mode) take effect on a
  # fresh process; --fork-demo uses the silent generator (no mic / no permission dialog).
  xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" --fork-demo >/dev/null
  sleep 2   # let the layout settle
  xcrun simctl io "$DEVICE" screenshot "$OUT/$1.png"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
}

# The faceplate is always a dark graphite "device" color regardless of the system
# light/dark setting (see ToneTheme), so light-mode captures are visually redundant.
# Ship one distinct shot per state/feature instead: in-tune, sharp, and the FORK
# reference-tone screen.
xcrun simctl ui "$DEVICE" appearance dark
shoot dark 440 "01-in-tune"
shoot dark 448 "02-sharp"
fork_shoot "03-fork"

echo "✓ wrote screenshots to $OUT"
ls -1 "$OUT"
