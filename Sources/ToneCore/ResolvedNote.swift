import Foundation

/// 周波数を最寄りの平均律音へ解決した結果。
public struct ResolvedNote: Equatable, Sendable {
    public let name: NoteName
    /// 科学的音高表記 (A4 = 440 で `octave == 4`)。
    public let octave: Int
    /// 最寄り音からのずれ。定義上 `-50...+50`。
    public let cents: Int
    /// 解決に使った入力周波数 (Hz)。
    public let frequency: Double

    public init(name: NoteName, octave: Int, cents: Int, frequency: Double) {
        self.name = name
        self.octave = octave
        self.cents = cents
        self.frequency = frequency
    }
}
