import Foundation

/// リファレンストーンとして鳴らす音名とオクターブ。
public struct ToneSelection: Equatable, Sendable {
    public let name: NoteName
    public let octave: Int

    public init(name: NoteName, octave: Int) {
        self.name = name
        self.octave = octave
    }

    /// MIDI ノート番号。
    public var midi: Int {
        (octave + 1) * 12 + NoteName.allCases.firstIndex(of: name)!
    }

    /// 基準ピッチを元にした 12 平均律周波数。
    public func frequency(referenceA4: Double) -> Double {
        referenceA4 * pow(2.0, Double(midi - 69) / 12.0)
    }
}

/// リファレンストーン選択の範囲。
public enum ToneRange {
    public static let minOctave: Int = 2
    public static let maxOctave: Int = 6
    public static let defaultSelection = ToneSelection(name: .A, octave: 4)
}
