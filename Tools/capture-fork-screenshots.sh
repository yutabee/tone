#!/usr/bin/env bash
# Capture FORK-mode (timbre selection) screenshots for docs/PR, in dark + light,
# using the DEBUG `--fork-demo` launch flag so no microphone / permission dialog.
# Output: docs/screenshots/  (App Store assets in fastlane/ are NOT touched.)
#
# Usage: bash Tools/capture-fork-screenshots.sh
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

# bundle ID はハードコードせず、実際にビルドした .app から読む。project.yml の
# 既定 (jp.syncbloom.tone) と、release 用に pbxproj をローカル変更した値
# (com.yutabee.tone) の両方で、必ず「いま起動するバイナリ」の ID を使う。
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "▶ bundle: $BUNDLE_ID"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
# 旧バイナリを確実に置換するため uninstall してから install する
# (install のみだと古い実体が残り --fork-demo 非対応版が動くことがある)。
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
# --fork-demo は無音スタブ (SilentToneGenerator) で AudioKit を構成しないため
# 本来ダイアログは出ないが、保険でマイク権限を事前付与しておく。
xcrun simctl privacy "$DEVICE" grant microphone "$BUNDLE_ID" 2>/dev/null || true

shoot() { # <appearance> <timbre> <name>
  xcrun simctl ui "$DEVICE" appearance "$1"
  # --terminate-running-process: 既存インスタンスを必ず終了させ、新しい起動引数
  # (--fork-demo / --fork-timbre) を適用した fresh プロセスで撮る(さもなくば
  # 既存インスタンスを前面化するだけで引数が反映されない)。
  xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" \
    --fork-demo "--fork-timbre=$2" >/dev/null
  sleep 2   # let the layout settle
  xcrun simctl io "$DEVICE" screenshot "$OUT/$3.png"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
}

shoot dark  fork     "fork-timbre-dark"
shoot light triangle "fork-timbre-light"

echo "✓ wrote screenshots to $OUT"
ls -1 "$OUT" | grep fork-timbre
