import Testing
import Foundation
@testable import ToneCore

@MainActor
@Suite("TunerViewModel+Tone")
struct TunerViewModelToneTests {
    private func makeViewModel(
        engine: MockPitchEngine = MockPitchEngine(),
        generator: MockToneGenerator = MockToneGenerator(),
        store: InMemoryReferencePitchStore = InMemoryReferencePitchStore(),
        timbreStore: InMemoryToneTimbreStore = InMemoryToneTimbreStore(),
        clock: TestClock = TestClock(),
        referenceA4: Double = 440
    ) -> TunerViewModel {
        TunerViewModel(
            engine: engine,
            processor: TuningProcessor(converter: NoteConverter(referenceA4: referenceA4)),
            store: store,
            clock: clock,
            toneGenerator: generator,
            timbreStore: timbreStore,
            engineStartRetryDelays: []
        )
    }

    private func freq(_ name: NoteName, _ octave: Int, ref: Double = 440) -> Double {
        ToneSelection(name: name, octave: octave).frequency(referenceA4: ref)
    }

    /// AC6: enterToneMode で engine.stop が呼ばれ mode==.tone, isTonePlaying==false。
    @Test
    func ac6_enterToneMode() {
        let engine = MockPitchEngine()
        let vm = makeViewModel(engine: engine)
        vm.enterToneMode()
        #expect(engine.stopCallCount == 1)
        #expect(vm.mode == .tone)
        #expect(vm.isTonePlaying == false)
    }

    /// AC7: toggleTone 1 回で play(選択×REF) が呼ばれ isTonePlaying==true、2 回目で stop・false。
    @Test
    func ac7_toggleTone() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()

        vm.toggleTone()
        #expect(gen.playCallCount == 1)
        #expect(abs((gen.lastFrequency ?? -1) - freq(.A, 4)) < 1e-9)
        #expect(vm.isTonePlaying == true)

        vm.toggleTone()
        #expect(gen.stopCallCount == 1)
        #expect(vm.isTonePlaying == false)
    }

    /// AC8: 再生中 selectToneNote(.C) で play が C の新周波数で再呼び出し。停止中は play を呼ばない。
    @Test
    func ac8_selectNoteWhilePlaying() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()

        // 停止中の選択変更は play を呼ばない。
        vm.selectToneNote(.C)
        #expect(gen.playCallCount == 0)
        #expect(vm.toneSelection.name == .C)

        vm.toggleTone()                 // 再生開始(C4)
        let beforeCount = gen.playCallCount
        vm.selectToneNote(.D)           // 再生中の変更 → 周波数更新
        #expect(gen.playCallCount == beforeCount + 1)
        #expect(abs((gen.lastFrequency ?? -1) - freq(.D, 4)) < 1e-9)
    }

    /// AC9: adjustToneOctave が [2,6] にクランプ(B6 で +1 据え置き、C2 で -1 据え置き)。
    @Test
    func ac9_octaveClamp() {
        let vm = makeViewModel()
        vm.enterToneMode()
        // 既定 A4 から最大まで上げる。
        vm.adjustToneOctave(+5)
        #expect(vm.toneSelection.octave == ToneRange.maxOctave)
        vm.adjustToneOctave(+1)
        #expect(vm.toneSelection.octave == ToneRange.maxOctave) // 据え置き
        vm.adjustToneOctave(-10)
        #expect(vm.toneSelection.octave == ToneRange.minOctave)
        vm.adjustToneOctave(-1)
        #expect(vm.toneSelection.octave == ToneRange.minOctave) // 据え置き
    }

    /// AC10: 再生中 setReferenceA4(442) で play が新 REF の周波数で呼ばれる。
    @Test
    func ac10_referenceFollowsWhilePlaying() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.toggleTone()                 // A4 @ 440
        let before = gen.playCallCount
        vm.setReferenceA4(442)
        #expect(gen.playCallCount == before + 1)
        #expect(abs((gen.lastFrequency ?? -1) - freq(.A, 4, ref: 442)) < 1e-9)
    }

    /// AC11: exitToneMode で stop(再生中)→ granted なら engine.start 経路、mode==.tuner。
    @Test
    func ac11_exitToneModeGranted() async {
        let engine = MockPitchEngine()
        engine.permissionResult = .granted
        let gen = MockToneGenerator()
        let vm = makeViewModel(engine: engine, generator: gen)
        await vm.onAppear()             // granted → start (count 1)
        vm.enterToneMode()              // stop (count 1)
        vm.toggleTone()                 // 再生開始
        await vm.exitToneMode()
        #expect(gen.stopWithoutDeactivatingCallCount >= 1)
        #expect(vm.mode == .tuner)
        #expect(engine.startCallCount == 2)   // onAppear + exit 復帰
        #expect(vm.state == .listening)
    }

    /// AC12: play が throw する mock で toggleTone を呼ぶと isTonePlaying==false のまま。
    @Test
    func ac12_playThrowKeepsStopped() {
        let gen = MockToneGenerator()
        gen.playError = .engineUnavailable
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.toggleTone()
        #expect(vm.isTonePlaying == false)
    }

    /// AC13: mode==.tuner で toggleTone は no-op(play/stop 未呼び出し)。
    @Test
    func ac13_toggleNoopInTunerMode() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.toggleTone()
        vm.selectToneNote(.C)
        vm.adjustToneOctave(+1)
        #expect(gen.playCallCount == 0)
        #expect(gen.stopCallCount == 0)
    }

    /// AC14: lifecycle ゲート — mode==.tone で handle/evaluateSilence が state 不変、retry で engine.start 未発火。
    @Test
    func ac14_lifecycleGated() async {
        let engine = MockPitchEngine()
        engine.permissionResult = .granted
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()             // start count 1, state .listening
        vm.enterToneMode()              // mode .tone

        engine.emit(PitchReading(frequency: 440, amplitude: 0.5, timestamp: 0))
        #expect(vm.state == .listening) // reading 無視
        vm.evaluateSilence()
        #expect(vm.state == .listening) // silence 無視

        await vm.retry()
        #expect(engine.startCallCount == 1) // tone 中は再起動しない
    }

    /// AC15: exitToneMode permission 分岐 — denied は .permissionDenied、engine.start 未発火。
    @Test
    func ac15_exitToneModeDenied() async {
        let engine = MockPitchEngine()
        engine.permissionResult = .denied
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()             // denied → .permissionDenied (start 0)
        vm.enterToneMode()
        await vm.exitToneMode()
        #expect(vm.state == .permissionDenied)
        #expect(engine.startCallCount == 0)
        #expect(vm.mode == .tuner)
    }

    /// AC16: onStopped 同期 — 再生中の simulateStop(.interruption) で false、以後 select は play しない。
    @Test
    func ac16_onStoppedSync() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.toggleTone()                 // 再生中
        gen.simulateStop(.interruption)
        #expect(vm.isTonePlaying == false)

        let before = gen.playCallCount
        vm.selectToneNote(.C)           // 意図しない再発音なし
        #expect(gen.playCallCount == before)
    }

    /// 背景化(onDisappear)時、tone モードで再生中なら toneGenerator.stop が呼ばれ
    /// isTonePlaying==false に同期する(復帰時に自動再生しない / 状態遷移表)。
    @Test
    func onDisappearStopsToneWhilePlaying() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.toggleTone()                 // 再生中
        #expect(vm.isTonePlaying == true)

        vm.onDisappear()
        #expect(gen.stopCallCount >= 1)
        #expect(vm.isTonePlaying == false)
    }

    /// AC17: play throw 共通ポリシー — 更新中の throw で isTonePlaying==false、選択/REF は最新を保持。
    @Test
    func ac17_throwPolicyOnUpdate() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.toggleTone()                 // 再生開始(throw なし)
        #expect(vm.isTonePlaying == true)

        gen.playError = .engineUnavailable
        vm.selectToneNote(.C)           // 更新時 throw
        #expect(vm.isTonePlaying == false)
        #expect(vm.toneSelection.name == .C)        // 選択は保持

        gen.playError = .engineUnavailable
        vm.adjustToneOctave(+1)
        #expect(vm.toneSelection.octave == 5)       // 変更は保持

        gen.playError = .engineUnavailable
        vm.setReferenceA4(442)
        #expect(vm.referenceA4 == 442)              // REF は保持
    }
}
