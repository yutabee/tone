import Foundation

/// リファレンストーンの音色。純粋ドメイン型(AudioKit 非依存)。
/// 表示文言・VoiceOver 読みは ToneUI(`TunerCopy`)側に置き、enum 自体は識別子のみを持つ。
public enum ToneTimbre: String, CaseIterable, Sendable {
    case sine
    case triangle
    case sawtooth
    case fork        // FM 合成による音叉 / ベル系の温かい音

    /// 未保存 / 未知 rawValue からのフォールバック既定音色。
    public static let `default`: ToneTimbre = .sine
}

/// 選択音色の永続化。既存 `ReferencePitchStore` と同じ「1 設定 = 1 ストア」パターン。
/// テストで in-memory 実装を注入する。
public protocol ToneTimbreStore: AnyObject {
    /// 保存済み音色。未保存 / 未知 rawValue は `nil`(呼出側が `default` にフォールバック)。
    func load() -> ToneTimbre?
    func save(_ timbre: ToneTimbre)
}
