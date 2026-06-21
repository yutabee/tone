# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-21

First public release. App version is set by `MARKETING_VERSION` in
`project.yml`; see [docs/RELEASE.md](docs/RELEASE.md) for the App Store runbook.

### Added
- **Chromatic tuner.** Microphone pitch detection showing note, octave, and cents
  deviation on a linear scale, with a single accent color and a haptic tap at the
  moment of lock.
- **Reference tone (FORK) mode.** A note/octave-selectable tone generator to tune
  against by ear, with no microphone required.
- **Adjustable reference pitch.** A4 from 415 to 466 Hz.
- **Liquid Glass–inspired interface** in light and dark, built with SwiftUI
  materials (runs on iOS 17+).
- **Accessibility.** VoiceOver (single labeled readout), Dynamic Type, Reduce
  Transparency, Increase Contrast, and Reduce Motion support.
- **Privacy by design.** Fully offline, no accounts, no analytics, no third-party
  tracking SDKs; audio is processed on-device and never recorded or transmitted.

[Unreleased]: https://github.com/yutabee/tone/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yutabee/tone/releases/tag/v1.0.0
