import Testing
import Foundation
@testable import ToneCore

@MainActor
@Suite("TunerViewModel")
struct TunerViewModelTests {
    private func makeViewModel(
        engine: MockPitchEngine,
        store: InMemoryReferencePitchStore = InMemoryReferencePitchStore(),
        clock: TestClock = TestClock(),
        referenceA4: Double = 440
    ) -> TunerViewModel {
        TunerViewModel(
            engine: engine,
            processor: TuningProcessor(converter: NoteConverter(referenceA4: referenceA4)),
            store: store,
            clock: clock
        )
    }

    /// AC6: setReferenceA4 は 415...466 にクランプ。
    @Test
    func ac6_referenceClamp() {
        let vm = makeViewModel(engine: MockPitchEngine())
        vm.setReferenceA4(500)
        #expect(vm.referenceA4 == 466)
        vm.setReferenceA4(400)
        #expect(vm.referenceA4 == 415)
    }

    /// AC7: 有効フレーム到来で state == .tuning(A4, inTune)。
    @Test
    func ac7_readingDrivesTuningState() async {
        let engine = MockPitchEngine()
        engine.permissionResult = .granted
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        engine.emit(PitchReading(frequency: 440, amplitude: 0.5, timestamp: 0))

        guard case let .tuning(note, inTune) = vm.state else {
            Issue.record("expected .tuning, got \(vm.state)")
            return
        }
        #expect(note.name == .A)
        #expect(note.octave == 4)
        #expect(inTune == true)
    }

    /// AC8: 検出後に無音タイムアウト → state == .listening(test clock 注入、sleep 不使用)。
    @Test
    func ac8_silenceReturnsToListening() async {
        let engine = MockPitchEngine()
        engine.permissionResult = .granted
        let clock = TestClock(now: 0)
        let vm = makeViewModel(engine: engine, clock: clock)
        await vm.onAppear()
        engine.emit(PitchReading(frequency: 440, amplitude: 0.5, timestamp: 0))
        clock.now = 1.01
        vm.evaluateSilence()
        #expect(vm.state == .listening)
    }

    /// AC9: 権限拒否 → state == .permissionDenied。
    @Test
    func ac9_permissionDenied() async {
        let engine = MockPitchEngine()
        engine.permissionResult = .denied
        let vm = makeViewModel(engine: engine)
        await vm.onAppear()
        #expect(vm.state == .permissionDenied)
    }

    /// AC11: 基準ピッチが同一 store 越しに別インスタンスへ復元される。
    @Test
    func ac11_referencePersists() async {
        let store = InMemoryReferencePitchStore()
        let vm1 = makeViewModel(engine: MockPitchEngine(), store: store)
        vm1.setReferenceA4(442)

        let engine2 = MockPitchEngine()
        engine2.permissionResult = .granted
        let vm2 = makeViewModel(engine: engine2, store: store)
        await vm2.onAppear()
        #expect(vm2.referenceA4 == 442)
    }

    /// AC14: start() の throw が state == .engineError(...) に分離される(.permissionDenied と区別)。
    @Test
    func ac14_engineErrorStates() async {
        let engine1 = MockPitchEngine()
        engine1.permissionResult = .granted
        engine1.startError = .inputUnavailable
        let vm1 = makeViewModel(engine: engine1)
        await vm1.onAppear()
        #expect(vm1.state == .engineError(.inputUnavailable))

        let engine2 = MockPitchEngine()
        engine2.permissionResult = .granted
        engine2.startError = .engineUnavailable
        let vm2 = makeViewModel(engine: engine2)
        await vm2.onAppear()
        #expect(vm2.state == .engineError(.engineUnavailable))
    }
}
