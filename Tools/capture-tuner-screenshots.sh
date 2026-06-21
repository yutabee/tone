#!/usr/bin/env bash
# Capture TUNER-mode screenshots (in-tune / sharp, dark + light) for docs/PR,
# using the DEBUG `--tone-demo` launch flag so no microphone / permission dialog.
# Output: docs/screenshots/  (App Store assets in fastlane/ are NOT touched.)
# Device is fixed to a 6.9" class so the size matches fork-timbre-*.png.
#
# Usage: bash Tools/capture-tuner-screenshots.sh
set -euo pipefail

DEVICE="${SIM_DEVICE:-iPhone 17 Pro Max}"   # 6.9" class (1320×2868)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/screenshots"
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

# bundle ID はハードコードせず、実際にビルドした .app から読む
# (project.yml の既定 com.yutabee.tone でも、ローカルで別 ID にしていても、
# 必ず「いま起動するバイナリ」の ID を使う)。
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "▶ bundle: $BUNDLE_ID"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
# 旧バイナリを確実に置換するため uninstall してから install する。
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
# --tone-demo は擬似 engine で AudioKit を構成しないため本来ダイアログは出ないが保険。
xcrun simctl privacy "$DEVICE" grant microphone "$BUNDLE_ID" 2>/dev/null || true

shoot() { # <appearance> <hz> <name>
  xcrun simctl ui "$DEVICE" appearance "$1"
  # --terminate-running-process: 既存インスタンスを終了させ、新しい起動引数を適用した
  # fresh プロセスで撮る (さもなくば前面化するだけで引数が反映されない)。
  xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" \
    --tone-demo "--tone-demo-hz=$2" >/dev/null
  sleep 3   # let the cents EMA settle
  xcrun simctl io "$DEVICE" screenshot "$OUT/$3.png"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
}

shoot dark  440 "in-tune-dark"
shoot dark  448 "sharp-dark"
shoot light 440 "in-tune-light"
shoot light 448 "sharp-light"

echo "✓ wrote screenshots to $OUT"
ls -1 "$OUT" | grep -E 'in-tune|sharp'
