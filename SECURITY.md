# Security Policy

## Reporting a vulnerability

Please report security or privacy issues **privately** — do not open a public
issue for anything exploitable.

- Preferred: use GitHub's private vulnerability reporting —
  **[Report a vulnerability](https://github.com/yutabee/tone/security/advisories/new)**
  (Security → Advisories on the repository).

Please include enough detail to reproduce: affected version, device / iOS version,
and steps. You'll get an acknowledgement, and a fix or assessment will follow.
This is a small single-maintainer project, so response is best-effort.

## Scope and design posture

Tone is built to have a minimal attack surface:

- **Fully offline.** The app makes no network connections and has no backend,
  accounts, or sign-in. There is no server-side component in scope.
- **No data collection.** No analytics or tracking, and no third-party ad /
  analytics SDKs. The App Privacy manifest declares no collected data
  (`App/PrivacyInfo.xcprivacy`); see [docs/privacy-policy.md](docs/privacy-policy.md).
- **Microphone audio stays on device.** Audio is processed in real time to
  estimate pitch and is never recorded, stored, or transmitted.
- **Third-party code** is limited to the open-source audio libraries
  [AudioKit](https://github.com/AudioKit/AudioKit) and
  [SoundpipeAudioKit](https://github.com/AudioKit/SoundpipeAudioKit), which run
  on-device.

## Secrets and the repository

This repository is public. Release credentials (App Store Connect API key, signing
certificates, provisioning profiles, Team ID) are **never committed** — they are
read from environment variables and gitignored local files. See
[docs/RELEASE.md](docs/RELEASE.md) and `.gitignore`. If you believe a secret has
been committed, report it through the private channel above.

## Supported versions

As a single-app project, only the latest released version receives fixes.
