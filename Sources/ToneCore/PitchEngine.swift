import Foundation

/// マイク権限状態。
public enum PermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

/// 検出器の致命的エラー。権限拒否(`.permissionDenied` state)とは区別する。
public enum PitchEngineError: Error, Equatable, Sendable {
    /// AVAudioEngine 起動失敗 / media services reset。
    case engineUnavailable
    /// 入力ルート無し / 他アプリが入力を占有。
    case inputUnavailable
}

/// ピッチ検出器の抽象(差替 / モック注入点)。
///
/// 配送は必ず main actor。実装はオーディオスレッドのコールバックを main へ marshaling する責務を持つ。
@MainActor
public protocol PitchEngine: AnyObject {
    /// 有効フレームごとに呼ばれる。`stop()` 後は呼ばれない。
    var onReading: (@MainActor (PitchReading) -> Void)? { get set }
    /// 初回ダイアログを伴う権限要求(非同期)。
    func requestPermission() async -> PermissionState
    /// `granted` 前提で開始。冪等(二重 `start` は no-op)。
    func start() throws
    /// 停止。冪等。
    func stop()
}
