# Releasing Tone to the App Store

This is the end-to-end runbook. Steps marked **(human)** need your Apple account,
payment, or a manual decision and cannot be automated.

## Release paths — which one to use

Three layers, in order of preference. **Prefer CI; raw xcodebuild is a fallback.**

| Path | When | How |
|---|---|---|
| **CI — GitHub Actions (primary)** | Cutting a real release | `.github/workflows/release.yml` (see next section) |
| **Local fastlane** | One-off from your Mac | `fastlane beta` / `submit` / `release` (§A) — needs the env in §1 + signing in §A |
| **Raw xcodebuild (fallback)** | fastlane unavailable | §3–§9 — manual archive / export / upload |

### CI release (GitHub Actions) — primary

`release.yml` runs the same fastlane lanes on a `macos` runner, so no local Mac
state is required to ship.

- **Triggers**: push a `v*` tag → `beta` (build + TestFlight, **no** submission);
  **Actions → Release → Run workflow → lane = `submit`** → review + auto-release
  (kept manual because submission is irreversible).
- **Build number**: auto-derived as *latest TestFlight build + 1*
  (`fastlane next_build_number`), so it never collides — no manual
  `CURRENT_PROJECT_VERSION` bump for the binary. Still bump `MARKETING_VERSION`
  for a new user-facing version.
- **Required GitHub Secrets** (Settings → Secrets and variables → Actions):
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8` (`.p8` base64), `DEVELOPMENT_TEAM`,
  `DIST_CERT_P12` (Apple Distribution `.p12` base64), `DIST_CERT_PASSWORD`,
  `DIST_PROFILE` (`Tone App Store` profile base64).
- **Cert / profile renewal**: both expire (~1 yr). On expiry, re-export and update
  `DIST_CERT_P12` / `DIST_PROFILE`.

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

## A. Local fastlane — fastlane + App Store Connect API key
Auth uses an **App Store Connect API key (.p8)** — no Apple ID password, no 2FA, and
no expiring session. The key replaces both spaceauth and the app-specific password.
After the app record exists, one command does build → upload → metadata → submit.

One-time: App Store Connect → **Users and Access → Integrations → App Store Connect API**
→ generate a Team key with the **App Manager** role → download `AuthKey_XXXXXXXXXX.p8`
(downloadable once) → note the **Key ID** and **Issuer ID** (Issuer ID is at the top of the page).

```bash
brew install fastlane xcodegen
export DEVELOPMENT_TEAM=XXXXXXXXXX                  # 10-char Team ID
export ASC_KEY_ID=XXXXXXXXXX                        # the key's Key ID
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   # Issuer ID
export ASC_KEY_FILEPATH="$HOME/.private_keys/AuthKey_XXXXXXXXXX.p8"  # path to the .p8

fastlane ensure_app   # creates the App ID + App Store Connect record (idempotent) — replaces step 2
fastlane release      # build+sign → upload binary + metadata + screenshots → SUBMIT for review
```
`fastlane release` ends by **submitting for review (irreversible)**. To stop short of
that: run `fastlane metadata` (text + screenshots) and `fastlane beta` (TestFlight)
instead, then submit by hand in App Store Connect.

The pure-Xcode path below (steps 3–9) is the fallback if you don't use fastlane.

### Distribution signing (one-time, manual)
The App Manager API-key role can **upload** but cannot **create signing certificates**,
so cloud signing (`-allowProvisioningUpdates`) fails at export. Release builds therefore
use **manual signing** against assets you install once:

1. **Apple Distribution certificate** — `developer.apple.com/account` → Certificates → **+**
   → *Apple Distribution*. Generate a CSR locally (Keychain Access → Certificate Assistant →
   *Request a Certificate from a Certificate Authority*, "Saved to disk"), upload it, download
   the `.cer`, and double-click to import into your **login** keychain. Verify:
   ```bash
   security find-identity -p codesigning -v   # shows "Apple Distribution: <name> (<team id>)"
   ```
2. **App Store provisioning profile** — Profiles → **+** → *App Store* → App ID
   `com.yutabee.tone` → the distribution cert above → **name it exactly `Tone App Store`**.
   Download and double-click to install (lands in `~/Library/MobileDevice/Provisioning Profiles/`).

`project.yml` pins these on the Tone target's **Release** config only
(`CODE_SIGN_IDENTITY: "Apple Distribution"`, `PROVISIONING_PROFILE_SPECIFIER: "Tone App Store"`)
so the setting never bleeds into the SPM dependencies. Once both are installed,
`fastlane beta` / `fastlane release` archive + export + upload with no further signing input.

## 2. **(human)** Register the app in App Store Connect
1. `developer.apple.com/account` → Identifiers → register App ID `com.yutabee.tone` (Explicit).
2. App Store Connect → My Apps → **+** → New App:
   - Platform: iOS · Name: **Tone Tuner** (the bare "Tone" is already taken on the App Store; the on-device name stays **Tone**) · Primary language: English (U.S.)
   - Bundle ID: `com.yutabee.tone` · SKU: `tone-ios-1`
3. Set the **Privacy Policy URL** (App Privacy section):
   `https://github.com/yutabee/tone/blob/main/docs/privacy-policy.md`
   (or enable GitHub Pages on `/docs` for a cleaner URL).
4. App Privacy → **Data Not Collected** (matches `App/PrivacyInfo.xcprivacy`).

> **§3–§9 are the raw-xcodebuild FALLBACK.** Prefer CI (`release.yml`) or local
> `fastlane` (§A); use these only when fastlane is unavailable. `ExportOptions.plist`
> is used **only** by this path — fastlane passes its export options inline, so the
> `REPLACE_WITH_TEAM_ID` placeholder there matters only if you run §5 by hand.

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
- Drafts live in `fastlane/metadata/{en-US,ja}/` and screenshots in `fastlane/screenshots/en-US/`.
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
