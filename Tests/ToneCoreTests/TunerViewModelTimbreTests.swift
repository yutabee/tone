import Testing
import Foundation
@testable import ToneCore

@MainActor
@Suite("TunerViewModel+Timbre")
struct TunerViewModelTimbreTests {
    private func makeViewModel(
        engine: MockPitchEngine = MockPitchEngine(),
        generator: MockToneGenerator = MockToneGenerator(),
        timbreStore: InMemoryToneTimbreStore = InMemoryToneTimbreStore(),
        referenceA4: Double = 440
    ) -> TunerViewModel {
        TunerViewModel(
            engine: engine,
            processor: TuningProcessor(converter: NoteConverter(referenceA4: referenceA4)),
            store: InMemoryReferencePitchStore(),
            clock: TestClock(),
            toneGenerator: generator,
            timbreStore: timbreStore
        )
    }

    /// AC-T1: init 直後(onAppear 前)は .default(=sine)。ストアに値があっても読まない。
    @Test
    func acT1_initDefaultBeforeOnAppear() {
        let timbreStore = InMemoryToneTimbreStore(initial: .fork)
        let vm = makeViewModel(timbreStore: timbreStore)
        #expect(vm.toneTimbre == .sine)
        #expect(timbreStore.loadCallCount == 0)   // init では load を呼ばない
    }

    /// AC-T2: load()==nil の状態で onAppear 後 → .sine。
    @Test
    func acT2_onAppearRestoresDefaultWhenEmpty() async {
        let timbreStore = InMemoryToneTimbreStore(initial: nil)
        let vm = makeViewModel(timbreStore: timbreStore)
        await vm.onAppear()
        #expect(vm.toneTimbre == .sine)
        #expect(timbreStore.loadCallCount == 1)   // onAppear で 1 回復元する
    }

    /// AC-T2b: 非 default の状態で onAppear し load()==nil → .default(=sine) に戻る
    /// (onAppear 再入時に旧値が残らない明示フォールバックを検証)。
    @Test
    func acT2b_onAppearResetsToDefaultWhenStoreEmpty() async {
        let timbreStore = InMemoryToneTimbreStore()
        let vm = makeViewModel(timbreStore: timbreStore)
        vm.enterToneMode()
        vm.selectToneTimbre(.fork)                 // 現在値を非 default に(store にも保存される)
        #expect(vm.toneTimbre == .fork)
        timbreStore.simulateExternalClear()        // 外部要因で永続値が消えた状況
        await vm.onAppear()                        // load()==nil → default に戻る
        #expect(vm.toneTimbre == .sine)
    }

    /// AC-T3: load()==.fork の状態で onAppear 後 → .fork。
    @Test
    func acT3_onAppearRestoresStoredTimbre() async {
        let vm = makeViewModel(timbreStore: InMemoryToneTimbreStore(initial: .fork))
        await vm.onAppear()
        #expect(vm.toneTimbre == .fork)
    }

    /// AC-T4: 音叉モードで selectToneTimbre(.triangle) → toneTimbre 更新 + save。
    @Test
    func acT4_selectPersists() {
        let timbreStore = InMemoryToneTimbreStore()
        let vm = makeViewModel(timbreStore: timbreStore)
        vm.enterToneMode()
        vm.selectToneTimbre(.triangle)
        #expect(vm.toneTimbre == .triangle)
        #expect(timbreStore.stored == .triangle)
        #expect(timbreStore.saveCallCount == 1)
    }

    /// AC-T5: 再生中 selectToneTimbre(.sawtooth) → play が新音色で再呼び。
    @Test
    func acT5_selectWhilePlayingReapplies() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.toggleTone()                          // 再生開始(.sine)
        let before = gen.playCallCount
        vm.selectToneTimbre(.sawtooth)
        #expect(gen.playCallCount == before + 1)
        #expect(gen.lastTimbre == .sawtooth)
    }

    /// AC-T6: 停止中 selectToneTimbre(.fork) → play 未呼び、状態 + save のみ。
    @Test
    func acT6_selectWhileStopped() {
        let gen = MockToneGenerator()
        let timbreStore = InMemoryToneTimbreStore()
        let vm = makeViewModel(generator: gen, timbreStore: timbreStore)
        vm.enterToneMode()
        vm.selectToneTimbre(.fork)
        #expect(gen.playCallCount == 0)
        #expect(vm.toneTimbre == .fork)
        #expect(timbreStore.stored == .fork)
    }

    /// AC-T7: チューナーモードで selectToneTimbre は no-op(状態不変・save 未呼び)。
    @Test
    func acT7_noopInTunerMode() {
        let timbreStore = InMemoryToneTimbreStore()
        let vm = makeViewModel(timbreStore: timbreStore)
        vm.selectToneTimbre(.triangle)           // mode==.tuner
        #expect(vm.toneTimbre == .sine)
        #expect(timbreStore.saveCallCount == 0)
    }

    /// AC-T8: playSelectedTone 成功時 play に現在の toneTimbre が渡る。
    @Test
    func acT8_playUsesCurrentTimbre() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.selectToneTimbre(.triangle)           // 停止中 → 状態のみ
        vm.toggleTone()                          // 再生開始
        #expect(gen.lastTimbre == .triangle)
    }

    /// AC-T9: 再生中に同一音色を再選択 → 冪等(toneTimbre 不変・save 呼び・play は同 freq/timbre で再呼び)。
    @Test
    func acT9_reselectSameTimbreIdempotent() {
        let gen = MockToneGenerator()
        let timbreStore = InMemoryToneTimbreStore()
        let vm = makeViewModel(generator: gen, timbreStore: timbreStore)
        vm.enterToneMode()
        vm.toggleTone()                          // 再生開始(.sine)
        let beforeCount = gen.playCallCount
        let beforeFreq = gen.lastFrequency
        vm.selectToneTimbre(.sine)               // 同一音色
        #expect(vm.toneTimbre == .sine)
        #expect(timbreStore.saveCallCount == 1)
        #expect(gen.playCallCount == beforeCount + 1)
        #expect(gen.lastTimbre == .sine)
        #expect(gen.lastFrequency == beforeFreq)
    }

    /// AC-T10: 再生中に play が throw する状態で selectToneTimbre → stop + isTonePlaying==false。
    @Test
    func acT10_selectThrowKeepsStopped() {
        let gen = MockToneGenerator()
        let vm = makeViewModel(generator: gen)
        vm.enterToneMode()
        vm.toggleTone()                          // 再生開始
        #expect(vm.isTonePlaying == true)

        gen.playError = .engineUnavailable
        vm.selectToneTimbre(.fork)               // 更新時 throw
        #expect(vm.isTonePlaying == false)
        #expect(vm.toneTimbre == .fork)          // 選択自体は保持
        #expect(gen.stopCallCount >= 1)
    }
}

@Suite("UserDefaultsToneTimbreStore")
struct UserDefaultsToneTimbreStoreTests {
    private func makeStore(suite: String) -> (UserDefaultsToneTimbreStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserDefaultsToneTimbreStore(defaults: defaults), defaults)
    }

    /// AC-T11: save→load round-trip。
    @Test
    func acT11_roundTrips() {
        let (store, _) = makeStore(suite: "tone.test.timbre.roundtrip")
        store.save(.fork)
        #expect(store.load() == .fork)
    }

    /// AC-T11: 未保存は nil。
    @Test
    func acT11_loadNilWhenEmpty() {
        let (store, _) = makeStore(suite: "tone.test.timbre.empty")
        #expect(store.load() == nil)
    }

    /// AC-T11: 未知 rawValue は nil(将来 case 削除でクラッシュしない)。
    @Test
    func acT11_loadNilForUnknownRawValue() {
        let (store, defaults) = makeStore(suite: "tone.test.timbre.unknown")
        defaults.set("ondes-martenot", forKey: "tone.timbre")
        #expect(store.load() == nil)
    }

    /// AC-T11: `tone.timbre` キーで rawValue 永続化。
    @Test
    func acT11_persistsUnderExpectedKey() {
        let (store, defaults) = makeStore(suite: "tone.test.timbre.key")
        store.save(.sawtooth)
        #expect(defaults.string(forKey: "tone.timbre") == "sawtooth")
    }
}
