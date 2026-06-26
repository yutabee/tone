import Testing
import Foundation
@testable import ToneCore

/// マイク信頼性まわりの ViewModel 契約:
/// #1 起動失敗の bounded retry、#4 システム要因停止の `.engineError` 反映、#7 再起動前の権限再確認。
@MainActor
@Suite("TunerViewModel+Reliability")
struct TunerViewModelReliabilityTests {
    private func makeViewModel(
        engine: MockPitchEngine,
        retryDelays: [Duration] = []
    ) -> TunerViewModel {
        TunerViewModel(
            engine: engine,
            processor: TuningProcessor(converter: NoteConverter(referenceA4: 440)),
            store: InMemoryReferencePitchStore(),
            clock: TestClock(),
            toneGenerator: MockToneGenerator(),
            timbreStore: InMemoryToneTimbreStore(),
            engineStartRetryDelays: retryDelays
        )
    }

    /// #4: システム要因停止(`onStopped`)が `.engineError` に反映される。
    @Test
    func onStoppedSurfacesEngineError() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        #expect(vm.state == .listening)

        engine.simulateStop(.engineUnavailable)
        #expect(vm.state == .engineError(.engineUnavailable))
    }

    /// #4: 音叉モード中は pitch エンジンの停止通知を無視する(検出は止めてある)。
    @Test
    func onStoppedIgnoredInToneMode() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        vm.enterToneMode()

        engine.simulateStop(.engineUnavailable)
        if case .engineError = vm.state {
            Issue.record("tone モードでは engineError にしない。実際: \(vm.state)")
        }
    }

    /// #1: 付与直後の transient な起動失敗は bounded retry で吸収し、最終的に `.listening`。
    @Test
    func transientStartFailureRecoversViaRetry() async {
        let engine = MockPitchEngine()
        engine.startErrorSequence = [.engineUnavailable, nil] // 1回失敗 → 成功
        let vm = makeViewModel(engine: engine, retryDelays: [.zero])
        await vm.onAppear()

        #expect(vm.state == .listening)
        #expect(engine.startCallCount == 2)
    }

    /// #1: retry を使い切っても失敗し続けるなら `.engineError`。
    @Test
    func permanentStartFailureExhaustsRetriesToEngineError() async {
        let engine = MockPitchEngine()
        engine.startError = .engineUnavailable
        let vm = makeViewModel(engine: engine, retryDelays: [.zero, .zero]) // 3 attempts
        await vm.onAppear()

        #expect(vm.state == .engineError(.engineUnavailable))
        #expect(engine.startCallCount == 3)
    }

    /// #7: 起動後に権限が取り消された状態で retry すると `.permissionDenied` に誘導する
    /// (古い `.engineError` / 無音 `.listening` で塞がない)。
    @Test
    func retryRechecksPermissionAndRoutesToDenied() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        #expect(vm.state == .listening)

        engine.currentPermissionResult = .denied // 設定アプリで取り消し
        await vm.retry()

        #expect(vm.state == .permissionDenied)
        // 権限が無いので engine.start() は呼ばない(onAppear の 1 回のみ)。
        #expect(engine.startCallCount == 1)
    }

    /// #7: 権限 granted のままなら retry は正常に検出を再開する。
    @Test
    func retryRestartsWhenPermissionStillGranted() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        await vm.retry()

        #expect(vm.state == .listening)
        #expect(engine.startCallCount == 2)
    }

    /// リグレッションガード: backoff 待機中に音叉モードへ移ったら、起き直したループは
    /// `engine.start()` を呼び直さない(停止後のマイク再起動を防ぐ世代ガード)。
    @Test
    func modeChangeDuringBackoffAbortsRetry() async {
        let engine = MockPitchEngine()
        engine.startErrorSequence = [.engineUnavailable] // attempt 1 失敗 → 本来 attempt 2 で成功
        let vm = makeViewModel(engine: engine, retryDelays: [.milliseconds(200)])

        async let appearing: Void = vm.onAppear() // start() 失敗 → 200ms backoff へ
        try? await Task.sleep(for: .milliseconds(20)) // sleep 到達を待つ
        vm.enterToneMode() // backoff 中にモード変更(世代を進める)
        await appearing

        #expect(engine.startCallCount == 1) // backoff 後に再 start しない
        #expect(vm.mode == .tone)
    }
}
