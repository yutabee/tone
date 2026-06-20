# Tone

An ad-free, fully-offline iOS chromatic tuner with a native iOS 26 Liquid Glass interface.

No ads. No accounts. No analytics. No feature bloat. One screen that does one thing — tell you the pitch — and gets out of the way. The differentiation isn't a louder feature list; it's a calm, modern, genuinely private tuner.

## Design

Tone adopts iOS 26's **Liquid Glass** language — translucent material, depth, and light — and spends its boldness in a single place: the moment your note locks in.

- **Floating glass readout.** The note, cents value, and ruler sit on a translucent `.ultraThinMaterial` card with a specular edge and a soft elevation shadow, layered over a quiet colored gradient so the glass has light to refract.
- **One accent, earned.** The interface stays monochrome until the pitch is in tune (|cents| ≤ 3); at that instant the note, indicator, and center tick lock to a single emerald-teal signal — and in the dark they emit a soft glow.
- **Linear cents, not a dial.** A hairline ruler from −50 to +50 cents with an indicator proportional to the deviation. Easier to read than a swinging needle.
- **Haptic lock.** A success haptic confirms the lock, so you don't have to keep watching the screen.
- **Rounded SF Pro** for the hero note, generous whitespace, and the reference pitch on a glass pill.

## Screenshots

### Dark

| Tuning (sharp) | In tune (locked) |
|---|---|
| ![sharp dark](docs/screenshots/sharp-dark.png) | ![in tune dark](docs/screenshots/in-tune-dark.png) |

### Light

| Tuning (sharp) | In tune (locked) |
|---|---|
| ![sharp light](docs/screenshots/sharp-light.png) | ![in tune light](docs/screenshots/in-tune-light.png) |

The accent appears only at the moment of lock. In dark mode the readout glows like a lit instrument; in light mode the glass frosts to a soft mint.

## Architecture

Domain logic (`TuningProcessor` / `NoteConverter`) is separated from SwiftUI and AudioKit. `PitchEngine`, `Clock`, and `ReferencePitchStore` are injected as protocols, so the core is unit-testable without audio hardware.

```
App (ToneApp)  ── injects concrete types
  └─ TunerScreen (ToneUI)         single SwiftUI screen / engine-agnostic
       ↕ observes
     TunerViewModel (ToneCore)    @MainActor @Observable state machine
       ├─ PitchEngine  ──▶ AudioKitPitchEngine (ToneAudio, iOS)  ← swap point
       ├─ TuningProcessor (pure) ── NoteConverter, cents-space EMA, silence, in-tune
       ├─ ReferencePitchStore ──▶ UserDefaultsReferencePitchStore
       └─ Clock ──▶ MonotonicClock
```

SPM targets:

| Target | Role | Platforms |
|---|---|---|
| `ToneCore` | Domain value types / logic / protocols (no AudioKit, no SwiftUI) | iOS / macOS (`swift test`) |
| `ToneAudio` | `AudioKitPitchEngine` (AVAudioSession / PitchTap) | iOS |
| `ToneUI` | SwiftUI views (engine-agnostic) | iOS / macOS |
| app shell | `@main ToneApp` + Info.plist + assets | iOS (Xcode project) |

## Build / Run

```bash
# Unit-test the domain logic (macOS)
swift test

# Generate the iOS app project (project.yml is the source of truth; .xcodeproj is generated)
brew install xcodegen   # if not installed
xcodegen generate
open Tone.xcodeproj      # run on device / simulator from Xcode
```

DEBUG builds accept a `--tone-demo` launch argument (optionally `--tone-demo-hz=<value>`) to feed a synthetic signal, so the UI can be verified without a microphone.

## Accessibility

- **VoiceOver** — the readout is a single labeled element (`"A sharp octave 4, 42 cents flat"` / `"… in tune"`); the decorative ruler is hidden.
- **Dynamic Type** — the hero note scales with the user's text size (`@ScaledMetric`).
- **Reduce Transparency** — glass falls back to opaque elevated surfaces.
- **Increase Contrast** — the background gradient and glow collapse; ink and hairlines are boosted.
- **Reduce Motion** — the indicator snaps instead of springing.

## Privacy

Fully offline. No network, accounts, or analytics, and no third-party (ad / analytics) SDKs. Microphone audio is processed on-device and is never recorded or transmitted. The App Privacy manifest declares no data collection (`App/PrivacyInfo.xcprivacy`).

## Status

- **M1** — domain logic + tests: done (AC1–12, 14; `swift test`)
- **M2** — AudioKit integration + Foundation adapters: done (iOS compile-verified; on-device pitch check pending)
- **M3** — SwiftUI UI + app shell: done (simulator-verified)
- **Liquid Glass UI** — current design direction (documented in this README)

## License

MIT — see [LICENSE](LICENSE).

Pitch detection via [AudioKit](https://github.com/AudioKit/AudioKit) / [SoundpipeAudioKit](https://github.com/AudioKit/SoundpipeAudioKit) (MIT). Structural reference: [ZenTuner](https://github.com/jpsim/ZenTuner) / [TunePro](https://github.com/timdubbins/TunePro).
