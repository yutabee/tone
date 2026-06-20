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
        // TODO(codex): 上記アルゴリズムを実装する。受け入れ: AC1〜AC5。
        return nil
    }
}
