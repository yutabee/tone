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
        if let storedReferenceA4 = store.load() {
            updateReferenceA4(storedReferenceA4, shouldSave: false)
        }

        engine.onReading = { [weak self] reading in
            self?.handle(reading)
        }

        state = .requestingPermission

        switch await engine.requestPermission() {
        case .granted:
            startEngine()
        case .denied:
            state = .permissionDenied
        case .notDetermined:
            state = .requestingPermission
        }
    }

    /// 画面離脱で検出を止める。
    public func onDisappear() {
        engine.stop()
    }

    /// 基準ピッチ変更: `415...466` にクランプ → `store.save` → `processor` / `converter` を再構築し
    /// `referenceA4` を更新する。
    public func setReferenceA4(_ hz: Double) {
        updateReferenceA4(hz, shouldSave: true)
    }

    /// `engineError` からの再試行。
    public func retry() async {
        startEngine()
    }

    /// 無音評価。UI 更新周期(`TimelineView` / タイマー)から呼ぶ。
    /// `clock.now` を使って `processor.evaluateSilence` を適用し、無音なら `.listening` へ反映する。
    public func evaluateSilence() {
        tuningState = processor.evaluateSilence(tuningState, now: clock.now)
        applyTuningStateToViewState()
    }

    private func handle(_ reading: PitchReading) {
        tuningState = processor.ingest(tuningState, reading)
        applyTuningStateToViewState()
    }

    private func applyTuningStateToViewState() {
        switch state {
        case .permissionDenied, .engineError:
            return
        case .idle, .requestingPermission, .listening, .tuning:
            break
        }

        if let note = tuningState.note {
            state = .tuning(note: note, inTune: tuningState.inTune)
            return
        }

        switch state {
        case .listening, .tuning:
            state = .listening
        case .idle, .requestingPermission, .permissionDenied, .engineError:
            break
        }
    }

    private func startEngine() {
        do {
            try engine.start()
            state = .listening
        } catch let error as PitchEngineError {
            state = .engineError(error)
        } catch {
            state = .engineError(.engineUnavailable)
        }
    }

    private func updateReferenceA4(_ hz: Double, shouldSave: Bool) {
        let clamped = min(max(hz, 415.0), 466.0)
        if shouldSave {
            store.save(clamped)
        }

        processor = TuningProcessor(
            converter: NoteConverter(referenceA4: clamped),
            config: processor.config
        )
        referenceA4 = clamped
    }
}
