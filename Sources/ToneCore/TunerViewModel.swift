import Foundation
import Observation

/// 1 画面チューナーの状態を保持する ViewModel。
///
/// AudioKit / SwiftUI には依存せず、`PitchEngine` / `TuningProcessor` / `ReferencePitchStore` / `Clock`
/// を protocol 注入する。モックだけで全状態遷移をテストできる。
@MainActor
@Observable
public final class TunerViewModel {
    public enum State: Equatable {
        /// 起動直後。
        case idle
        /// 初回許可ダイアログ表示中。
        case requestingPermission
        /// 許可済み・音を拾えていない(無音)。
        case listening
        /// 検出中。
        case tuning(note: ResolvedNote, inTune: Bool)
        /// 権限拒否(設定アプリ導線を表示)。
        case permissionDenied
        /// 検出器エラー(再試行導線を表示)。
        case engineError(PitchEngineError)
    }

    public private(set) var state: State = .idle
    public private(set) var referenceA4: Double

    private let engine: any PitchEngine
    private var processor: TuningProcessor
    private let store: any ReferencePitchStore
    private let clock: any Clock
    private var tuningState = TuningState()

    public init(
        engine: any PitchEngine,
        processor: TuningProcessor,
        store: any ReferencePitchStore,
        clock: any Clock
    ) {
        self.engine = engine
        self.processor = processor
        self.store = store
        self.clock = clock
        self.referenceA4 = processor.converter.referenceA4
    }

    /// 起動シーケンス: `store.load()` で基準ピッチ復元 → `requestPermission()` →
    /// `.granted` なら `engine.start()`(成功で `.listening` / 失敗で `.engineError`)、
    /// `.denied` なら `.permissionDenied`。`onReading` の配線もここで行う。
    public func onAppear() async {
        // TODO(codex): spec「起動シーケンス」を実装する。受け入れ: AC9, AC14。
    }

    /// 画面離脱で検出を止める。
    public func onDisappear() {
        // TODO(codex): engine.stop() を呼ぶ。
    }

    /// 基準ピッチ変更: `415...466` にクランプ → `store.save` → `processor` / `converter` を再構築し
    /// `referenceA4` を更新する。
    public func setReferenceA4(_ hz: Double) {
        // TODO(codex): spec「基準ピッチ」を実装する。受け入れ: AC6, AC11。
    }

    /// `engineError` からの再試行。
    public func retry() async {
        // TODO(codex): engine.start() を再試行し state を更新する。
    }

    /// 無音評価。UI 更新周期(`TimelineView` / タイマー)から呼ぶ。
    /// `clock.now` を使って `processor.evaluateSilence` を適用し、無音なら `.listening` へ反映する。
    public func evaluateSilence() {
        // TODO(codex): spec「無音判定」を実装する。受け入れ: AC8。
    }
}
