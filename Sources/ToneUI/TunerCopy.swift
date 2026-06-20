import Foundation
import ToneCore

/// 初版はシステム言語に応じて日本語または英語の固定文言のみ(動的切替・追加言語は対象外)。
/// 画面表示と VoiceOver 読み上げの両方をここに集約する。
struct TunerCopy {
    enum Language { case ja, en }

    let language: Language

    init(locale: Locale = .current) {
        let code = locale.language.languageCode?.identifier
        self.language = (code == "ja") ? .ja : .en
    }

    private func t(_ ja: String, _ en: String) -> String { language == .ja ? ja : en }

    // 状態ラベル(画面)
    var listening: String { t("音を鳴らしてください", "Play a note") }
    var starting: String { t("起動中", "Starting") }
    var requestingPermission: String { t("マイクの許可を確認中", "Checking microphone access") }
    var inTune: String { t("合っています", "In tune") }
    var flat: String { t("低い", "Flat") }
    var sharp: String { t("高い", "Sharp") }

    // 権限拒否
    var permissionTitle: String { t("マイクへのアクセスが必要です", "Microphone access needed") }
    var permissionBody: String {
        t("設定アプリで Tone にマイクを許可すると、音程を表示できます。",
          "Allow microphone access for Tone in Settings to see pitch.")
    }
    var openSettings: String { t("設定を開く", "Open Settings") }

    // エンジンエラー
    var engineErrorTitle: String { t("マイクを使えませんでした", "Couldn't use the microphone") }
    var engineErrorBody: String {
        t("ほかのアプリが使用中か、入力が見つかりません。もう一度お試しください。",
          "Another app may be using it, or no input was found. Try again.")
    }
    var inputUnavailableBody: String {
        t("マイク入力が見つかりません。接続を確認してもう一度お試しください。",
          "No microphone input found. Check your connection and try again.")
    }
    var retry: String { t("もう一度", "Try again") }

    // 基準ピッチ
    func reference(_ hz: Double) -> String {
        let value = Int(hz.rounded())
        return language == .ja ? "基準 A\(value) Hz" : "Ref A\(value) Hz"
    }
    var lowerReference: String { t("基準を下げる", "Lower reference") }
    var raiseReference: String { t("基準を上げる", "Raise reference") }

    // VoiceOver: 音名 + 高い/低い/合っている
    func noteAccessibilityLabel(_ note: ResolvedNote, inTune: Bool) -> String {
        let name = spokenNoteName(note.name)
        let octave = note.octave
        if language == .ja {
            if inTune { return "\(name) オクターブ\(octave)、合っています" }
            let dir = note.cents < 0 ? "低い" : "高い"
            return "\(name) オクターブ\(octave)、\(abs(note.cents)) セント\(dir)"
        } else {
            if inTune { return "\(name) octave \(octave), in tune" }
            let dir = note.cents < 0 ? "flat" : "sharp"
            return "\(name) octave \(octave), \(abs(note.cents)) cents \(dir)"
        }
    }

    private func spokenNoteName(_ name: NoteName) -> String {
        let isSharp = name.displayText.contains("\u{266F}")
        let letter = String(name.displayText.first ?? "A")
        if !isSharp { return letter }
        return language == .ja ? "\(letter) シャープ" : "\(letter) sharp"
    }
}
