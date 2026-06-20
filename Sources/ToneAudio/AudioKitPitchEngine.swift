import Foundation

/// `ToneAudio` モジュールのプラットフォーム可用性マーカー。
/// macOS では実機オーディオエンジンを提供しない(`swift test` は ToneCore のみで完結する)。
public enum ToneAudioModule {
    /// 実機 `AudioKitPitchEngine` が利用可能なプラットフォームか。
    public static let isPitchEngineAvailable: Bool = {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }()
}

#if os(iOS)
import AVFoundation
import AudioKit
import SoundpipeAudioKit
import ToneCore

/// `PitchEngine` の本番実装。AudioKit の `PitchTap`(`SoundpipeAudioKit`)で単音ピッチを検出し、
/// `AVAudioSession` のライフサイクル / 割り込み / route 変更 / media reset を扱う。
///
/// オーディオスレッドのコールバックは必ず main actor へ marshaling してから `onReading` を呼ぶ。
@MainActor
public final class AudioKitPitchEngine: PitchEngine {
    public var onReading: (@MainActor (PitchReading) -> Void)?

    /// `PitchReading.timestamp` を打つための monotonic 時刻源。ViewModel の無音判定と同じ基準に揃える。
    private let clock: any Clock

    public init(clock: any Clock = MonotonicClock()) {
        self.clock = clock
    }

    /// iOS 17+ の `AVAudioApplication.requestRecordPermission` で権限を要求する。
    public func requestPermission() async -> PermissionState {
        // TODO(codex): 現在の権限状態を確認し、未決なら要求して PermissionState を返す。
        fatalError("unimplemented: requestPermission")
    }

    /// `granted` 前提で `AVAudioSession`(`.record` / `.measurement`)を有効化し、
    /// `AudioEngine` + `PitchTap`(bufferSize 4096)を起動する。冪等。
    public func start() throws {
        // TODO(codex): セッション有効化 + エンジン/タップ起動 + 通知購読。失敗は PitchEngineError で投げる。
        fatalError("unimplemented: start")
    }

    /// タップ停止 + セッション無効化。冪等。stop 後は onReading を呼ばない。
    public func stop() {
        // TODO(codex): タップ停止 + エンジン停止 + セッション無効化 + 通知解除。
        fatalError("unimplemented: stop")
    }
}
#endif
