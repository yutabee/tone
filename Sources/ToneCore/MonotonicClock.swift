import Foundation

/// `DispatchTime`(端末起動からの monotonic 経過)で `now` を返す本番 `Clock`。
/// システム時刻の変更や巻き戻りの影響を受けない(無音タイムアウトの計測に使う)。
public final class MonotonicClock: Clock {
    public init() {}

    public var now: TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
