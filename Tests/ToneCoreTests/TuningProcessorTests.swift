import Testing
import Foundation
@testable import ToneCore

@Suite("TuningProcessor")
struct TuningProcessorTests {
    private func makeProcessor(
        referenceA4: Double = 440,
        config: TuningConfig = TuningConfig()
    ) -> TuningProcessor {
        TuningProcessor(converter: NoteConverter(referenceA4: referenceA4), config: config)
    }

    /// AC7: 440 Hz の有効フレーム → note A4・inTune・lastValidAt 更新。
    @Test
    func ac7_detectsNote() {
        let processor = makeProcessor()
        let state = processor.ingest(
            TuningState(),
            PitchReading(frequency: 440, amplitude: 0.5, timestamp: 0)
        )
        #expect(state.note?.name == .A)
        #expect(state.note?.octave == 4)
        #expect(state.inTune == true)
        #expect(state.lastValidAt == 0)
    }

    /// AC8: 検出後 silenceTimeout 超過 → note nil(無音)。
    @Test
    func ac8_silenceTimeoutClearsNote() {
        let processor = makeProcessor()
        let detected = processor.ingest(
            TuningState(),
            PitchReading(frequency: 440, amplitude: 0.5, timestamp: 0)
        )
        let silent = processor.evaluateSilence(detected, now: 1.01)
        #expect(silent.note == nil)
    }

    /// AC10: in-tune 境界 |cents| <= 3。3 cents → true、4 cents → false。
    @Test
    func ac10_inTuneBoundary() {
        let processor = makeProcessor()

        let threeCentsSharp = 440.0 * pow(2.0, 3.0 / 1200.0)
        let s3 = processor.ingest(
            TuningState(),
            PitchReading(frequency: threeCentsSharp, amplitude: 0.5, timestamp: 0)
        )
        #expect(s3.note?.cents == 3)
        #expect(s3.inTune == true)

        let fourCentsSharp = 440.0 * pow(2.0, 4.0 / 1200.0)
        let s4 = processor.ingest(
            TuningState(),
            PitchReading(frequency: fourCentsSharp, amplitude: 0.5, timestamp: 0)
        )
        #expect(s4.note?.cents == 4)
        #expect(s4.inTune == false)
    }

    /// AC12: 単発オクターブ飛び(440 → 880 → 440)。880 は外れ値棄却され 3 出力すべて A4。
    @Test
    func ac12_singleOctaveJumpRejected() {
        let processor = makeProcessor()
        var state = TuningState()
        var names: [NoteName?] = []
        var octaves: [Int?] = []
        for (index, frequency) in [440.0, 880.0, 440.0].enumerated() {
            state = processor.ingest(
                state,
                PitchReading(frequency: frequency, amplitude: 0.5, timestamp: TimeInterval(index))
            )
            names.append(state.note?.name)
            octaves.append(state.note?.octave)
        }
        #expect(names == [.A, .A, .A])
        #expect(octaves == [4, 4, 4])
    }

    /// 振幅ゲート: 低振幅フレームは無効で note も lastValidAt も更新しない。
    @Test
    func amplitudeGateRejectsQuietFrame() {
        let processor = makeProcessor()
        let state = processor.ingest(
            TuningState(),
            PitchReading(frequency: 440, amplitude: 0.0, timestamp: 0)
        )
        #expect(state.note == nil)
        #expect(state.lastValidAt == nil)
    }

    /// 無効入力(周波数 0)→ state 不変。
    @Test
    func invalidFrequencyLeavesStateUnchanged() {
        let processor = makeProcessor()
        let initial = TuningState()
        let state = processor.ingest(
            initial,
            PitchReading(frequency: 0, amplitude: 0.5, timestamp: 0)
        )
        #expect(state == initial)
    }
}
