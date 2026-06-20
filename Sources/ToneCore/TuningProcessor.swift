import Foundation

/// 平滑化 / 無音 / Note 変換 / in-tune 判定を集約した純ロジック(値型)。
/// UI・AudioKit・時計・永続化に依存しない。
public struct TuningProcessor: Equatable, Sendable {
    public let converter: NoteConverter
    public let config: TuningConfig

    public init(converter: NoteConverter, config: TuningConfig = TuningConfig()) {
        self.converter = converter
        self.config = config
    }

    /// 1 reading を取り込み新しい state を返す純関数。
    ///
    /// 手順(対数 = セント空間):
    /// 1. 無効入力(`reading.frequency <= 0` または非有限)→ state 不変。
    /// 2. 振幅ゲート: `reading.amplitude < config.amplitudeGate` → 無効フレーム。
    ///    `note` も `lastValidAt` も更新しない(state 不変)。
    /// 3. 有効フレーム: `m = 1200 · log2(f / converter.referenceA4)` を計算。
    ///    - `smoothedCentsFromRef == nil` なら初期受理: `smoothed = m`、`pendingOutlierCents = nil`。
    ///    - それ以外は外れ値判定: `abs(m - smoothed) > config.octaveRejectCents`。
    ///      - 外れ値かつ `pendingOutlierCents == nil`(単発)→ 棄却。
    ///        `pendingOutlierCents = m` のみ記録し、`note` / `smoothed` / `lastValidAt` は不変。
    ///      - 外れ値かつ `pendingOutlierCents != nil`(2 フレーム連続)→ 受理。
    ///        `smoothed = m`(EMA を新値へリセット)、`pendingOutlierCents = nil`。
    ///      - 非外れ値 → 受理。`smoothed = emaAlpha · m + (1 - emaAlpha) · smoothed`、
    ///        `pendingOutlierCents = nil`(保留中の外れ値を解消)。
    /// 4. 受理時: `f' = referenceA4 · 2^(smoothed / 1200)` を `converter.note(for:)` に通して `note` を得る。
    ///    `inTune = abs(note.cents) <= config.inTuneCents`、`lastValidAt = reading.timestamp`。
    public func ingest(_ state: TuningState, _ reading: PitchReading) -> TuningState {
        guard reading.frequency > 0, reading.frequency.isFinite else {
            return state
        }

        guard reading.amplitude >= config.amplitudeGate else {
            return state
        }

        let measuredCents = 1200.0 * log2(reading.frequency / converter.referenceA4)
        guard measuredCents.isFinite else {
            return state
        }

        var next = state
        let smoothedCents: Double

        if let currentSmoothed = state.smoothedCentsFromRef {
            let isOutlier = abs(measuredCents - currentSmoothed) > config.octaveRejectCents

            if isOutlier {
                guard state.pendingOutlierCents != nil else {
                    next.pendingOutlierCents = measuredCents
                    return next
                }

                smoothedCents = measuredCents
            } else {
                smoothedCents = config.emaAlpha * measuredCents + (1.0 - config.emaAlpha) * currentSmoothed
            }
        } else {
            smoothedCents = measuredCents
        }

        let smoothedFrequency = converter.referenceA4 * pow(2.0, smoothedCents / 1200.0)
        guard let note = converter.note(for: smoothedFrequency) else {
            return state
        }

        next.smoothedCentsFromRef = smoothedCents
        next.pendingOutlierCents = nil
        next.note = note
        next.inTune = abs(note.cents) <= config.inTuneCents
        next.lastValidAt = reading.timestamp
        return next
    }

    /// 無音タイムアウト評価。`lastValidAt` から `config.silenceTimeout` を超過していれば `note = nil`
    /// (無音)にする。`lastValidAt == nil` の場合は state 不変。
    public func evaluateSilence(_ state: TuningState, now: TimeInterval) -> TuningState {
        guard let lastValidAt = state.lastValidAt else {
            return state
        }

        guard now - lastValidAt > config.silenceTimeout else {
            return state
        }

        var next = state
        next.note = nil
        next.inTune = false
        return next
    }
}
