import Testing
import Foundation
@testable import ToneCore

@Suite("MonotonicClock")
struct MonotonicClockTests {
    /// `now` は正で、連続読み取りで非減少(monotonic)。
    @Test
    func nonDecreasingAndPositive() {
        let clock = MonotonicClock()
        let first = clock.now
        let second = clock.now
        #expect(first > 0)
        #expect(second >= first)
    }
}

@Suite("UserDefaultsReferencePitchStore")
struct UserDefaultsReferencePitchStoreTests {
    /// 各テストで独立した suite を使い standard defaults を汚さない。
    private func makeStore(suite: String) -> (UserDefaultsReferencePitchStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserDefaultsReferencePitchStore(defaults: defaults), defaults)
    }

    /// 未保存時は nil(復元側が 440 にフォールバックする前提)。
    @Test
    func loadReturnsNilWhenEmpty() {
        let (store, _) = makeStore(suite: "tone.test.refstore.empty")
        #expect(store.load() == nil)
    }

    /// save した値が load で復元される。
    @Test
    func saveThenLoadRoundTrips() {
        let (store, _) = makeStore(suite: "tone.test.refstore.roundtrip")
        store.save(442)
        #expect(store.load() == 442)
    }

    /// `tone.referenceA4` キーで永続化される。
    @Test
    func persistsUnderExpectedKey() {
        let (store, defaults) = makeStore(suite: "tone.test.refstore.key")
        store.save(415)
        #expect(defaults.object(forKey: "tone.referenceA4") != nil)
        #expect(defaults.double(forKey: "tone.referenceA4") == 415)
    }
}
