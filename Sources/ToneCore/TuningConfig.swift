import Foundation

/// チューニング処理の調整可能パラメータ。マジックナンバーをハードコードせず注入する。
public struct TuningConfig: Equatable, Sendable {
    /// セント空間 EMA 係数。
    public var emaAlpha: Double
    /// `|Δ cents|` がこれを超える単発フレームを外れ値として棄却する。
    public var octaveRejectCents: Double
    /// 無音タイムアウト秒。
    public var silenceTimeout: TimeInterval
    /// 相対振幅ゲート(これ未満のフレームは無効)。
    public var amplitudeGate: Double
    /// `|cents| <= inTuneCents` を in-tune とみなす。
    public var inTuneCents: Int

    public init(
        emaAlpha: Double = 0.2,
        octaveRejectCents: Double = 600,
        silenceTimeout: TimeInterval = 1.0,
        amplitudeGate: Double = 0.02,
        inTuneCents: Int = 3
    ) {
        self.emaAlpha = emaAlpha
        self.octaveRejectCents = octaveRejectCents
        self.silenceTimeout = silenceTimeout
        self.amplitudeGate = amplitudeGate
        self.inTuneCents = inTuneCents
    }
}

/// `TuningProcessor` が保持・更新する状態(純粋データ)。
public struct TuningState: Equatable, Sendable {
    /// `referenceA4` からの平滑化セント(連続量)。未検出なら `nil`。
    public var smoothedCentsFromRef: Double?
    /// 最後に有効フレームを取り込んだ時刻(`reading.timestamp`)。
    public var lastValidAt: TimeInterval?
    /// 現在の解決音。無音/未検出なら `nil`。
    public var note: ResolvedNote?
    /// `|note.cents| <= inTuneCents`。
    public var inTune: Bool
    /// オクターブ外れ値ヒステリシス用: 直前フレームが単発外れ値だった場合の cents 値。
    /// 2 フレーム連続で外れ値なら受理に転じるための内部追跡フィールド。
    public var pendingOutlierCents: Double?

    public init(
        smoothedCentsFromRef: Double? = nil,
        lastValidAt: TimeInterval? = nil,
        note: ResolvedNote? = nil,
        inTune: Bool = false,
        pendingOutlierCents: Double? = nil
    ) {
        self.smoothedCentsFromRef = smoothedCentsFromRef
        self.lastValidAt = lastValidAt
        self.note = note
        self.inTune = inTune
        self.pendingOutlierCents = pendingOutlierCents
    }
}
