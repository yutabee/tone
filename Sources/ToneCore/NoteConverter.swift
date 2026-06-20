import Foundation

/// 周波数 → 音名 の純関数変換。
public struct NoteConverter: Equatable, Sendable {
    /// 基準ピッチ。既定 440.0。クランプ責務は呼び出し側(`TunerViewModel.setReferenceA4`)が持つ。
    public let referenceA4: Double

    public init(referenceA4: Double = 440.0) {
        self.referenceA4 = referenceA4
    }

    /// 周波数を最寄りの平均律音へ解決する。
    ///
    /// アルゴリズム:
    /// - `frequency <= 0` または `!frequency.isFinite` → `nil`
    /// - `midi = round(69 + 12 · log2(f / referenceA4))`
    /// - `targetFreq = referenceA4 · 2^((midi - 69) / 12)`
    /// - `cents = Int(round(1200 · log2(f / targetFreq)))`  // 定義上 -50...+50
    /// - `name = NoteName.allCases[midi % 12]`、`octave = midi / 12 - 1`
    /// - タイブレーク: ちょうど ±50 cents は round-half-up により上隣の音へ寄せる(一意)
    public func note(for frequency: Double) -> ResolvedNote? {
        guard frequency > 0, frequency.isFinite, referenceA4 > 0, referenceA4.isFinite else {
            return nil
        }

        let midi = Int(round(69.0 + 12.0 * log2(frequency / referenceA4)))
        let targetFrequency = referenceA4 * pow(2.0, Double(midi - 69) / 12.0)
        let cents = Int(round(1200.0 * log2(frequency / targetFrequency)))
        let noteIndex = ((midi % 12) + 12) % 12
        let name = NoteName.allCases[noteIndex]
        let octave = Int(floor(Double(midi) / 12.0)) - 1

        return ResolvedNote(name: name, octave: octave, cents: cents, frequency: frequency)
    }
}
