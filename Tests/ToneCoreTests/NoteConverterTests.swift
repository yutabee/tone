import Testing
import Foundation
@testable import ToneCore

@Suite("NoteConverter")
struct NoteConverterTests {
    /// AC1: A4 = 440 Hz → (.A, 4, 0 cents)。
    @Test
    func ac1_a4IsZeroCents() {
        let note = NoteConverter(referenceA4: 440).note(for: 440)
        #expect(note == ResolvedNote(name: .A, octave: 4, cents: 0, frequency: 440))
    }

    /// AC2: 446.16 Hz → A4 で +24 cents(±1 許容、検算 +24.07c)。
    @Test
    func ac2_sharpA4() throws {
        let note = try #require(NoteConverter(referenceA4: 440).note(for: 446.16))
        #expect(note.name == .A)
        #expect(note.octave == 4)
        #expect(abs(note.cents - 24) <= 1)
    }

    /// AC3: 261.63 Hz → (.C, 4, 0 cents)(検算 +0.03c → 0)。
    @Test
    func ac3_middleC() {
        let note = NoteConverter(referenceA4: 440).note(for: 261.63)
        #expect(note?.name == .C)
        #expect(note?.octave == 4)
        #expect(note?.cents == 0)
    }

    /// AC4: 無効入力(0 / 負 / NaN / inf)はすべて nil。
    @Test(arguments: [0.0, -10.0, Double.nan, Double.infinity])
    func ac4_invalidInputIsNil(_ frequency: Double) {
        #expect(NoteConverter(referenceA4: 440).note(for: frequency) == nil)
    }

    /// AC5: referenceA4 = 442 で 442 Hz → (.A, 4, 0 cents)。
    @Test
    func ac5_alternateReference() {
        let note = NoteConverter(referenceA4: 442).note(for: 442)
        #expect(note?.name == .A)
        #expect(note?.octave == 4)
        #expect(note?.cents == 0)
    }
}
