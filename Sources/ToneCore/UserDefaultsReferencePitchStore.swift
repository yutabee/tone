import Foundation

/// `UserDefaults` 上に基準ピッチを永続化する本番 `ReferencePitchStore`。
/// キーは `tone.referenceA4`。未保存(キー無し)は `nil` を返し、復元側が 440 にフォールバックする。
public final class UserDefaultsReferencePitchStore: ReferencePitchStore {
    /// 永続化キー。将来キーを変える場合は読めなければ `nil`(= 440 フォールバック)に倒す。
    static let key = "tone.referenceA4"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Double? {
        // `double(forKey:)` は未保存時に 0.0 を返すため、キーの存在を先に確認して「未保存 = nil」を区別する。
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return defaults.double(forKey: Self.key)
    }

    public func save(_ hz: Double) {
        defaults.set(hz, forKey: Self.key)
    }
}
