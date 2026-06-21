# Contributing to Tone

Thanks for your interest in Tone. It's a small, focused app, so contributions are
welcome but kept deliberately minimal — bug fixes, accuracy improvements, tests,
and documentation are the easiest to land.

## You do not need an Apple Developer account

The domain logic and the iOS app both build **unsigned** in Debug, so you can build
and test everything without enrolling in the Apple Developer Program or configuring
signing. This is exactly what CI does on every push
(see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

Signing is only needed to distribute to the App Store, which is a maintainer task
documented in [`docs/RELEASE.md`](docs/RELEASE.md).

## Prerequisites

- macOS with Xcode (latest stable) and the Swift 6 toolchain.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for generating the iOS project:
  `brew install xcodegen`.

## Build and test

```bash
# 1. Unit-test the domain logic on macOS (no AudioKit, no simulator needed)
swift test

# 2. Generate the iOS app project (project.yml is the source of truth; the
#    .xcodeproj is generated and gitignored)
xcodegen generate

# 3. Open and run on a simulator or device
open Tone.xcodeproj
```

`ToneCore` is pure domain logic with no AudioKit or SwiftUI dependency, so most
behavior is testable with `swift test` alone. AudioKit and SwiftUI live at the
edges (`ToneAudio` / `ToneUI`) — see the architecture diagram in the
[README](README.md).

### Exercising the UI without a microphone

Debug builds accept launch arguments:

- `--tone-demo` (optionally `--tone-demo-hz=<value>`) feeds a synthetic pitch
  signal so the tuner UI can be verified without audio input.
- `--fork-demo` (optionally `--fork-timbre=<name>`) opens the reference-tone
  screen with a silent generator (used by the screenshot tooling in `Tools/`).

## Workflow and conventions

- **One task = one branch = one PR.** Branch names follow the type:
  `feat/<slug>`, `fix/<slug>`, `docs/<slug>`, `chore/<slug>`.
- Keep commits small and logical — one reviewable change per commit, with a
  message that explains *why*. Don't mix refactors with behavior changes.
- Add or update tests for behavior changes; keep `swift test` green.
- Match the surrounding code style. The project targets Swift 6 with strict
  concurrency; UI is SwiftUI, state is an `@Observable @MainActor` view model.
- Open an issue first for anything beyond a small fix, so the scope can be agreed
  before you invest time. Tone intentionally stays lean — feature additions are
  weighed against that.

## Reporting bugs

Use [GitHub Issues](https://github.com/yutabee/tone/issues). For anything that
looks like a security or privacy issue, follow [SECURITY.md](SECURITY.md) instead.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this project.
