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

    // 周波数読み取り
    var detected: String { t("検出", "Detected") }
    var target: String { t("目標", "Target") }

    // 音叉モード
    var tunerModeLabel: String { t("チューナーモード", "Tuner mode") }
    var toneModeLabel: String { t("音叉モード", "Tone mode") }
    var play: String { t("再生", "Play") }
    var stop: String { t("停止", "Stop") }
    var raiseOctave: String { t("オクターブを上げる", "Raise octave") }
    var lowerOctave: String { t("オクターブを下げる", "Lower octave") }

    func timbreLabel(_ timbre: ToneTimbre) -> String {
        switch timbre {
        case .sine:
            return t("サイン", "Sine")
        case .triangle:
            return t("三角", "Triangle")
        case .sawtooth:
            return t("ノコギリ", "Saw")
        case .fork:
            return t("音叉", "Fork")
        }
    }

    func timbreAccessibilityLabel(_ timbre: ToneTimbre) -> String {
        switch timbre {
        case .sine:
            return t("サイン波", "Sine")
        case .triangle:
            return t("三角波", "Triangle")
        case .sawtooth:
            return t("ノコギリ波", "Sawtooth")
        case .fork:
            return t("音叉、FM", "Tuning fork")
        }
    }

    /// オクターブ表示の集約読み上げ(OCT + 数値を 1 要素にまとめる)。
    func octaveValue(_ octave: Int) -> String {
        language == .ja ? "オクターブ \(octave)" : "Octave \(octave)"
    }

    /// 音名選択ボタンの読み(C / C シャープ …)。
    func toneNoteName(_ name: NoteName) -> String { spokenNoteName(name) }

    /// 音叉モードの集約読み上げ(音名 + オクターブ + 周波数 + 再生/停止)。
    func toneStatus(_ selection: ToneSelection, frequency: Double, playing: Bool) -> String {
        let name = spokenNoteName(selection.name)
        let octave = selection.octave
        let hz = Int(frequency.rounded())
        if language == .ja {
            return "\(name) オクターブ\(octave)、\(hz) ヘルツ、\(playing ? "再生中" : "停止中")"
        } else {
            return "\(name) octave \(octave), \(hz) hertz, \(playing ? "playing" : "stopped")"
        }
    }

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
