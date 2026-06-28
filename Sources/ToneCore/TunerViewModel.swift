import Foundation
import Observation

/// 1 画面チューナーの状態を保持する ViewModel。
///
/// AudioKit / SwiftUI には依存せず、`PitchEngine` / `TuningProcessor` / `ReferencePitchStore` / `Clock`
/// を protocol 注入する。モックだけで全状態遷移をテストできる。
@MainActor
@Observable
public final class TunerViewModel {
    public enum Mode: Equatable {
        case tuner
        case tone
    }

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
    public private(set) var mode: Mode = .tuner
    public private(set) var toneSelection: ToneSelection = ToneRange.defaultSelection
    /// 現在の選択音色。`init` では `.default`、`onAppear()` で `timbreStore` から復元する
    /// (基準ピッチ `referenceA4` の復元タイミングと揃える)。
    public private(set) var toneTimbre: ToneTimbre = .default
    public private(set) var isTonePlaying = false

    private let engine: any PitchEngine
    private var processor: TuningProcessor
    private let store: any ReferencePitchStore
    private let clock: any Clock
    private let toneGenerator: any ToneGenerator
    private let timbreStore: any ToneTimbreStore
    private var tuningState = TuningState()
    /// `engine.start()` 失敗時の retry 前 backoff。要素数 = retry 回数(総試行 = 1 + count)。
    /// 付与直後の HAL settle 待ちなど transient な失敗を吸収する。テストは `[]` / `[.zero]` を注入。
    private let retryDelays: [Duration]
    /// 進行中の起動試行を識別する世代印。停止 / モード変更 / 再起動で増やし、
    /// backoff から起きた古いループを無効化する(背景化後の再起動・二重起動を防ぐ)。
    private var startGeneration = 0
    /// 現在 scene が前面(.active)か。`setScenePhaseActive` が更新し、背景復帰の判定に使う。
    private var sceneActive = true
    private var hasAppeared = false

    public init(
        engine: any PitchEngine,
        processor: TuningProcessor,
        store: any ReferencePitchStore,
        clock: any Clock,
        toneGenerator: any ToneGenerator,
        timbreStore: any ToneTimbreStore,
        engineStartRetryDelays: [Duration] = [.milliseconds(120), .milliseconds(350)]
    ) {
        self.engine = engine
        self.processor = processor
        self.store = store
        self.clock = clock
        self.toneGenerator = toneGenerator
        self.timbreStore = timbreStore
        self.referenceA4 = processor.converter.referenceA4
        self.retryDelays = engineStartRetryDelays

        toneGenerator.onStopped = { [weak self] _ in
            self?.isTonePlaying = false
        }
    }

    /// 起動シーケンス: `store.load()` で基準ピッチ復元 → `requestPermission()` →
    /// `.granted` なら `engine.start()`(成功で `.listening` / 失敗で `.engineError`)、
    /// `.denied` なら `.permissionDenied`。`onReading` の配線もここで行う。
    public func onAppear() async {
        hasAppeared = true

        if let storedReferenceA4 = store.load() {
            updateReferenceA4(storedReferenceA4, shouldSave: false)
        }
        // 未保存 / 未知 rawValue は `.default` に明示フォールバックする
        // (onAppear 再入時に非 default の旧値が残らないよう if-let にしない)。
        toneTimbre = timbreStore.load() ?? .default

        engine.onReading = { [weak self] reading in
            self?.handle(reading)
        }
        engine.onStopped = { [weak self] error in
            self?.handleEngineStopped(error)
        }

        state = .requestingPermission

        switch await engine.requestPermission() {
        case .granted:
            await startEngine()
        case .denied:
            state = .permissionDenied
        case .notDetermined:
            state = .requestingPermission
        }
    }

    /// 画面離脱 / 背景化で検出を止める。tone モードで再生中なら参照トーンも止め
    /// `isTonePlaying` を同期する(復帰時に自動再生しない / 状態遷移表準拠)。
    public func onDisappear() {
        engine.stop()
        startGeneration += 1 // backoff 待機中の起動ループを無効化する(停止後の再起動を防ぐ)。
        if isTonePlaying {
            toneGenerator.stop()
            isTonePlaying = false
        }
    }

    /// scenePhase 連動のマイク制御。View は `.active`→`true` / `.background`→`false` を転送し、
    /// `.inactive`(Control Center / バナー / 権限ダイアログ)は転送しない。
    public func setScenePhaseActive(_ active: Bool) async {
        guard active else {
            setScenePhaseInactive()
            return
        }
        let was = sceneActive
        sceneActive = true
        guard hasAppeared, !was, mode == .tuner else { return }
        await startEngine()
    }

    /// 背景化 (.background)。停止は同期で即時実行し scene イベントの順序を保証する
    /// (View が Task で包まず直接呼ぶ → background→active 高速往復での task 順序逆転を防ぐ)。
    public func setScenePhaseInactive() {
        let was = sceneActive
        sceneActive = false
        guard hasAppeared, was else { return }
        engine.stop()
        startGeneration += 1
        if isTonePlaying {
            toneGenerator.stop()
            isTonePlaying = false
        }
    }

    /// 基準ピッチ変更: `415...466` にクランプ → `store.save` → `processor` / `converter` を再構築し
    /// `referenceA4` を更新する。
    public func setReferenceA4(_ hz: Double) {
        updateReferenceA4(hz, shouldSave: true)
        updatePlayingToneIfNeeded()
    }

    /// `engineError` からの再試行。
    public func retry() async {
        await startEngine()
    }

    /// 無音評価。UI 更新周期(`TimelineView` / タイマー)から呼ぶ。
    /// `clock.now` を使って `processor.evaluateSilence` を適用し、無音なら `.listening` へ反映する。
    public func evaluateSilence() {
        guard mode != .tone else { return }

        tuningState = processor.evaluateSilence(tuningState, now: clock.now)
        applyTuningStateToViewState()
    }

    /// 音叉モードへ移行し、検出器を停止する。再入(既に再生中)でも実出力を確実に止める。
    public func enterToneMode() {
        engine.stop()
        startGeneration += 1 // backoff 待機中の起動ループを無効化する。
        if isTonePlaying {
            toneGenerator.stop()
            isTonePlaying = false
        }
        mode = .tone
    }

    /// チューナーモードへ戻り、保持済みの権限状態に応じて検出を復帰する。
    public func exitToneMode() async {
        // isTonePlaying に依らず必ず tone を止める: 直前の toggleTone stop() が仕込んだ
        // 遅延 deactivate を tone 側の世代更新で無効化するため (handoff barrier)。
        // pitch が引き継げる (granted) ときだけ no-deactivate、引き継げないなら通常 stop() で
        // セッションを解放し他アプリ音声を復帰させる。
        if engine.currentPermission == .granted {
            toneGenerator.stopWithoutDeactivating()
        } else {
            toneGenerator.stop()
        }
        isTonePlaying = false
        mode = .tuner
        await startEngine()
    }

    /// 音叉モード中だけリファレンストーンの再生 / 停止を切り替える。
    public func toggleTone() {
        guard mode == .tone else { return }

        if isTonePlaying {
            toneGenerator.stop()
            isTonePlaying = false
            return
        }

        playSelectedTone()
    }

    /// 音叉モード中だけ音名を変更する。
    public func selectToneNote(_ name: NoteName) {
        guard mode == .tone else { return }

        toneSelection = ToneSelection(name: name, octave: toneSelection.octave)
        updatePlayingToneIfNeeded()
    }

    /// 音叉モード中だけオクターブを変更する。
    public func adjustToneOctave(_ delta: Int) {
        guard mode == .tone else { return }

        let octave = min(max(toneSelection.octave + delta, ToneRange.minOctave), ToneRange.maxOctave)
        toneSelection = ToneSelection(name: toneSelection.name, octave: octave)
        updatePlayingToneIfNeeded()
    }

    /// 音叉モード中だけ音色を変更する。永続化し、再生中なら新音色で即反映する。
    public func selectToneTimbre(_ timbre: ToneTimbre) {
        guard mode == .tone else { return }

        toneTimbre = timbre
        timbreStore.save(timbre)
        updatePlayingToneIfNeeded()
    }

    private func handle(_ reading: PitchReading) {
        guard mode != .tone else { return }

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

    /// システム要因(割り込み非復帰 / route 復帰失敗 / media reset 失敗)でエンジンが
    /// 止まったときの反映。tuner モードでのみ `.engineError` を出し、手動再試行導線を見せる。
    /// (`engine.stop()` 由来では発火しない契約。)
    private func handleEngineStopped(_ error: PitchEngineError) {
        guard mode != .tone else { return }
        state = .engineError(error)
    }

    /// 検出を開始する。起動前にマイク権限を再確認し(設定アプリでの取り消し検知)、
    /// `granted` のときだけ起動する。付与直後など transient な起動失敗は `retryDelays` の
    /// 範囲で再試行し、使い切ってから `.engineError` を出す
    /// (scenePhase / ボタンの手動「もう一度」が最終 fallback)。
    private func startEngine() async {
        guard mode != .tone, sceneActive else { return }

        switch engine.currentPermission {
        case .denied:
            state = .permissionDenied
            return
        case .notDetermined:
            return
        case .granted:
            break
        }

        // この起動試行に世代印を付ける。backoff 中に別の起動 / 停止(onDisappear)/ モード変更が
        // 来たら、起きた時点で世代不一致になり古いループは start() を呼ばず state も書かない。
        // = 背景化後のマイク再起動・二重起動・stale な終端状態の上書きを防ぐ。
        startGeneration += 1
        let generation = startGeneration

        var attempt = 0
        while true {
            do {
                try engine.start()
                state = .listening
                return
            } catch {
                let pitchError = (error as? PitchEngineError) ?? .engineUnavailable
                guard attempt < retryDelays.count else {
                    state = .engineError(pitchError)
                    return
                }
                do {
                    try await Task.sleep(for: retryDelays[attempt])
                } catch {
                    return // キャンセル(view 破棄など)で中断
                }
                attempt += 1
                // backoff 中に停止 / 起動し直し / 音叉モードへ移っていたら破棄する。
                guard generation == startGeneration, mode != .tone else { return }
            }
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

    private func updatePlayingToneIfNeeded() {
        guard mode == .tone, isTonePlaying else { return }

        playSelectedTone()
    }

    private func playSelectedTone() {
        do {
            try toneGenerator.play(frequency: toneSelection.frequency(referenceA4: referenceA4), timbre: toneTimbre)
            isTonePlaying = true
        } catch {
            // 失敗時は実出力を確実に止めて UI 状態と同期させる(旧音の鳴り残しを防ぐ)。
            toneGenerator.stop()
            isTonePlaying = false
        }
    }
}
