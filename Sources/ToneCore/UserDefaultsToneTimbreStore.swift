import Foundation

/// `UserDefaults` 上に選択音色を永続化する本番 `ToneTimbreStore`。
/// キーは `tone.timbre`(String rawValue)。未保存・未知 rawValue は `nil` を返し、復元側が `default` にフォールバックする。
public final class UserDefaultsToneTimbreStore: ToneTimbreStore {
    /// 永続化キー。将来 case を変える場合は読めなければ `nil`(= default フォールバック)に倒す。
    static let key = "tone.timbre"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ToneTimbre? {
        // 未保存(キー無し)と未知 rawValue をまとめて nil に倒す。
        guard let raw = defaults.string(forKey: Self.key) else { return nil }
        return ToneTimbre(rawValue: raw)
    }

    public func save(_ timbre: ToneTimbre) {
        defaults.set(timbre.rawValue, forKey: Self.key)
    }
}
