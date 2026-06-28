import Testing
import Foundation
@testable import ToneCore

/// scenePhase 連動のマイク取得 / 解放契約(A: firewall を View から VM へ移設)と
/// FORK→TUNER のセッション handoff(B: stopWithoutDeactivating)を検証する。
@MainActor
@Suite("TunerViewModel+Lifecycle")
struct TunerViewModelLifecycleTests {
    private func makeViewModel(
        engine: MockPitchEngine = MockPitchEngine(),
        tone: MockToneGenerator = MockToneGenerator()
    ) -> TunerViewModel {
        TunerViewModel(
            engine: engine,
            processor: TuningProcessor(converter: NoteConverter(referenceA4: 440)),
            store: InMemoryReferencePitchStore(),
            clock: TestClock(),
            toneGenerator: tone,
            timbreStore: InMemoryToneTimbreStore(),
            engineStartRetryDelays: []
        )
    }

    /// A: 背景化(`.background`)でマイクを停止する。
    @Test
    func backgroundStopsListening() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        #expect(vm.state == .listening)

        await vm.setScenePhaseActive(false)
        #expect(engine.stopCallCount >= 1)
    }

    /// A: 背景化 → 前面復帰でマイクを再開する(start 2 回目)。
    @Test
    func foregroundResumesAfterBackground() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        #expect(engine.startCallCount == 1)

        await vm.setScenePhaseActive(false)
        await vm.setScenePhaseActive(true)

        #expect(engine.startCallCount == 2)
        #expect(vm.state == .listening)
    }

    /// A: 背景化を挟まない再 `.active`(Control Center / バナー復帰)では再起動しない
    /// = `wasBackgrounded` firewall の VM 版。
    @Test
    func activeWithoutPriorBackgroundDoesNotRestart() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        #expect(engine.startCallCount == 1)

        await vm.setScenePhaseActive(true) // 既に前面のまま再通知 → 遷移なし
        #expect(engine.startCallCount == 1)
    }

    /// A: FORK モード中の前面復帰はマイクを取得しない(復帰時に自動再生もしない契約と整合)。
    @Test
    func foregroundInForkModeDoesNotAcquireMic() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        vm.enterToneMode()
        let startsBefore = engine.startCallCount

        await vm.setScenePhaseActive(false)
        await vm.setScenePhaseActive(true)

        #expect(engine.startCallCount == startsBefore)
        #expect(vm.mode == .tone)
    }

    /// B: `exitToneMode` は再生中のトーンを `stopWithoutDeactivating` で止める
    /// (直後に startEngine がセッションを引き継ぐため、トーン側は無効化しない)。
    @Test
    func exitToneModeUsesHandoffStop() async {
        let engine = MockPitchEngine()
        let tone = MockToneGenerator()
        let vm = makeViewModel(engine: engine, tone: tone)
        await vm.onAppear()
        vm.enterToneMode()
        vm.toggleTone() // 再生開始
        #expect(tone.isPlaying)

        await vm.exitToneMode()

        #expect(tone.stopWithoutDeactivatingCallCount == 1)
        #expect(tone.stopCallCount == 0)
        #expect(vm.mode == .tuner)
        #expect(engine.startCallCount >= 1)
    }

    /// A: 背景状態で `onAppear` してもマイクを起動しない(前面ギャップ修正)。
    /// 権限ダイアログ表示中にホームへ抜けた等で resume 後に盲目起動しないことを保証する。
    @Test
    func onAppearWhileBackgroundedDoesNotStart() async {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        await vm.setScenePhaseActive(false) // onAppear 前に背景化
        await vm.onAppear()
        #expect(engine.startCallCount == 0)

        await vm.setScenePhaseActive(true)
        #expect(engine.startCallCount == 1)
        #expect(vm.state == .listening)
    }
}
