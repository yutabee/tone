import Foundation

/// リファレンストーン生成器のエラー。
public enum ToneGeneratorError: Error, Equatable, Sendable {
    /// AVAudioEngine 起動失敗 / セッション有効化失敗 / media reset。
    case engineUnavailable
    /// `frequency <= 0` / `NaN` / `inf`。
    case invalidFrequency
}

/// ユーザ操作以外でリファレンストーンが停止した理由。
public enum ToneGeneratorStopReason: Equatable, Sendable {
    case interruption
    case routeChange
    case mediaServicesReset
}

/// リファレンストーン生成器の抽象(差替 / モック注入点)。
@MainActor
public protocol ToneGenerator: AnyObject {
    /// 非ユーザ要因停止で発火。`stop()` 由来では呼ばない。
    var onStopped: (@MainActor (ToneGeneratorStopReason) -> Void)? { get set }
    /// 再生開始 / 再生中は周波数更新(冪等な再設定)。非正 / 非有限は `invalidFrequency` を throw。
    func play(frequency: Double) throws
    /// 停止。冪等。`onStopped` は呼ばない。
    func stop()
}
