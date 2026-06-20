# Tone

広告ゼロ・完全オフラインの iOS クロマチックチューナー。スイス派ミニマルデザイン。

差別化は機能ではなく、**無広告・無課金・即起動・1 画面完結 + design craft**。市場の主要チューナーが抱える「広告地獄・基本機能のペイウォール・bloatware」の対極を志向する。

- 仕様: [`docs/specs/2026-06-20-tuner.md`](docs/specs/2026-06-20-tuner.md)
- 技術: SwiftUI (iOS 17+) + AudioKit / SoundpipeAudioKit (`PitchTap`)
- アーキテクチャ: ドメインロジック(`TuningProcessor` / `NoteConverter`)を SwiftUI・AudioKit から分離し、`PitchEngine` / `Clock` / `ReferencePitchStore` を protocol 注入してテスト可能に

## Status

仕様確定済み。実装は M1(ドメインロジック+テスト)→ M2(AudioKit 統合)→ M3(UI+提出)の順。

## License

MIT — [LICENSE](LICENSE)。ピッチ検出に [AudioKit](https://github.com/AudioKit/AudioKit) / [SoundpipeAudioKit](https://github.com/AudioKit/SoundpipeAudioKit) を使用。構造の参考に [ZenTuner](https://github.com/jpsim/ZenTuner) / [TunePro](https://github.com/timdubbins/TunePro)。
