# Releasing Tone to the App Store

This is the end-to-end runbook. Steps marked **(human)** need your Apple account,
payment, or a manual decision and cannot be automated.

## 0. One-time prerequisites
- **(human)** Apple Developer Program membership (enrolled).
- Your 10-character **Team ID** (App Store Connect → Membership, or `developer.apple.com/account`).
- Tools: `xcode-select --install`, `brew install xcodegen`, and optionally `brew install fastlane`.

## 1. Configure your Team ID (no secrets committed)
`project.yml` and `fastlane/Appfile` read the Team ID from the environment:
```bash
export DEVELOPMENT_TEAM=XXXXXXXXXX   # your 10-char Team ID
```
For the manual xcodebuild path (steps 3–9) also set `teamID` in `ExportOptions.plist`.

## A. Automated release — fastlane, manual auth (recommended)
No App Store Connect API key is shared. You authenticate once with 2FA; fastlane
then runs non-interactively from the session. After the app record exists, one
command does build → upload → metadata → submit.

```bash
brew install fastlane xcodegen
export DEVELOPMENT_TEAM=XXXXXXXXXX
export FASTLANE_USER=<your-apple-id>   # Developer Program 加入の Apple ID
# App-specific password (binary upload): appleid.apple.com → Sign-In and Security → App-Specific Passwords
export FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
# Complete 2FA in the prompt, then keep the printed session (~30 days):
export FASTLANE_SESSION="$(fastlane spaceauth -u "$FASTLANE_USER")"

fastlane ensure_app   # creates the App ID + App Store Connect record (idempotent) — replaces step 2
fastlane release      # build+sign → upload binary + metadata + screenshots → SUBMIT for review
```
`fastlane release` ends by **submitting for review (irreversible)**. To stop short of
that: run `fastlane metadata` (text + screenshots) and `fastlane beta` (TestFlight)
instead, then submit by hand in App Store Connect.

The pure-Xcode path below (steps 3–9) is the fallback if you don't use fastlane.

## 2. **(human)** Register the app in App Store Connect
1. `developer.apple.com/account` → Identifiers → register App ID `jp.syncbloom.tone` (Explicit).
2. App Store Connect → My Apps → **+** → New App:
   - Platform: iOS · Name: **Tone** · Primary language: English (or Japanese)
   - Bundle ID: `jp.syncbloom.tone` · SKU: `tone-ios-1`
3. Set the **Privacy Policy URL** (App Privacy section):
   `https://github.com/yutabee/tone/blob/main/docs/privacy-policy.md`
   (or enable GitHub Pages on `/docs` for a cleaner URL).
4. App Privacy → **Data Not Collected** (matches `App/PrivacyInfo.xcprivacy`).

## 3. Generate the Xcode project
```bash
xcodegen generate
```
(`Tone.xcodeproj` is generated from `project.yml` and is gitignored.)

## 4. Archive (Release, signed)
```bash
xcodebuild -project Tone.xcodeproj -scheme Tone -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Tone.xcarchive archive
```

## 5. Export the App Store .ipa
```bash
xcodebuild -exportArchive \
  -archivePath build/Tone.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```

## 6. Upload the binary
Pick one:
- **Xcode Organizer (simplest):** Window → Organizer → select the archive → *Distribute App* → App Store Connect → Upload.
- **CLI with an App Store Connect API key** (`developer.apple.com` → Keys → App Store Connect API → download `AuthKey_XXX.p8`):
  ```bash
  xcrun altool --upload-app -f build/export/Tone.ipa -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  ```
- **fastlane:** `bundle exec fastlane beta` (uploads to TestFlight) — see `fastlane/Fastfile`.

## 7. Metadata + screenshots
- Drafts live in `fastlane/metadata/{en-US,ja}/` and screenshots in `fastlane/screenshots/{en-US,ja}/`.
- Upload them: `bundle exec fastlane metadata` — **or** paste the text and drag the images in App Store Connect by hand.
- Required screenshot sizes: 6.9" (1320×2868) and 6.5"/6.7" iPhone. Generate with `Tools/capture-appstore-screenshots.sh`.

## 8. Export compliance
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is already set (Tone uses no
non-exempt encryption), so App Store Connect won't ask at every upload.

## 9. **(human)** Submit for review
In App Store Connect: attach the build, confirm metadata/screenshots, **Add for Review → Submit**.
Apple review is typically 1–3 days. Release is irreversible once live — this final step is yours.

## Version bumps (next releases)
Edit `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`, add a
`fastlane/metadata/<locale>/release_notes.txt`, then repeat from step 3.
