import Testing
import Foundation
@testable import ToneCore

@Suite("ToneSelection")
struct ToneSelectionTests {
    /// AC1: A4 は基準ピッチそのもの。
    @Test
    func ac1_a4EqualsReference() {
        let f = ToneSelection(name: .A, octave: 4).frequency(referenceA4: 440)
        #expect(abs(f - 440) < 1e-9)
    }

    /// AC2: 基準ピッチ追従(REF442 で A4 = 442)。
    @Test
    func ac2_followsReference() {
        let f = ToneSelection(name: .A, octave: 4).frequency(referenceA4: 442)
        #expect(abs(f - 442) < 1e-9)
    }

    /// AC3: C4 ≈ 261.6256 Hz(REF440)。
    @Test
    func ac3_c4Frequency() {
        let f = ToneSelection(name: .C, octave: 4).frequency(referenceA4: 440)
        #expect(abs(f - 261.6256) < 1e-3)
    }

    /// AC4: オクターブ +1 で周波数が 2 倍(A4 440 → A5 880)。
    @Test
    func ac4_octaveDoubles() {
        let a4 = ToneSelection(name: .A, octave: 4).frequency(referenceA4: 440)
        let a5 = ToneSelection(name: .A, octave: 5).frequency(referenceA4: 440)
        #expect(abs(a5 - a4 * 2) < 1e-6)
    }

    /// AC5: midi 番号 — A4→69, C4→60, C2→36, B6→95。
    @Test
    func ac5_midiNumbers() {
        #expect(ToneSelection(name: .A, octave: 4).midi == 69)
        #expect(ToneSelection(name: .C, octave: 4).midi == 60)
        #expect(ToneSelection(name: .C, octave: 2).midi == 36)
        #expect(ToneSelection(name: .B, octave: 6).midi == 95)
    }

    /// AC18(ToneCore 部): 既定選択の周波数は正の有限値。
    /// 異常 frequency の throw 検証(invalidFrequency)は ToneAudio(iOS, AudioKitToneGenerator)側。
    @Test
    func ac18_defaultSelectionFiniteFrequency() {
        let f = ToneRange.defaultSelection.frequency(referenceA4: 440)
        #expect(f.isFinite && f > 0)
        #expect(ToneRange.minOctave == 2)
        #expect(ToneRange.maxOctave == 6)
    }
}
