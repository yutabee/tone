import Foundation

/// マイク 1 フレーム分のピッチ検出結果(検出器 → ドメインの境界値型)。
public struct PitchReading: Equatable, Sendable {
    /// 検出周波数 (Hz)。`<= 0` / `NaN` / `inf` は無効入力として扱う。
    public let frequency: Double
    /// 生振幅。正規化レンジは保証されない(相対値)。
    public let amplitude: Double
    /// monotonic 秒 (`Clock.now`)。
    public let timestamp: TimeInterval

    public init(frequency: Double, amplitude: Double, timestamp: TimeInterval) {
        self.frequency = frequency
        self.amplitude = amplitude
        self.timestamp = timestamp
    }
}

/// 12 平均律の音名。`allCases` の順序がそのまま `midi % 12`(0 = C)に対応する。
public enum NoteName: String, CaseIterable, Sendable {
    case C, Csharp, D, Dsharp, E, F, Fsharp, G, Gsharp, A, Asharp, B
}
