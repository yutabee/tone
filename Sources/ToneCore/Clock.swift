import Foundation

/// monotonic 時刻源。テストで test clock を注入し、無音判定を決定的にする。
public protocol Clock: AnyObject {
    /// monotonic 秒。
    var now: TimeInterval { get }
}

/// 基準ピッチの永続化。テストで in-memory 実装を注入する。
public protocol ReferencePitchStore: AnyObject {
    func load() -> Double?
    func save(_ hz: Double)
}
