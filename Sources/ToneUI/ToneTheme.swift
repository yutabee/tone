import SwiftUI
import ToneCore

/// 実機チューナー筐体の視覚トークン。グラファイト面 + 計器窓 + 単一の signal(in-tune)アクセント。
/// 筐体は scheme に依らず常に dark(機材としての物理色)で、ロックの瞬間だけ signal が発光する。
/// 配色は `colorSchemeContrast` から解決し、increase-contrast 時は面取り・発光を畳んで可読性に倒す。
struct ToneTheme {
    let scheme: ColorScheme
    var contrast: ColorSchemeContrast = .standard

    var isDark: Bool { scheme == .dark }
    private var highContrast: Bool { contrast == .increased }

    // MARK: - Signal (in-tune)

    /// in-tune のときだけ現れる単一アクセント(emerald-teal、acid green を避ける)。
    /// dark は発光に耐えるよう僅かに luminance を上げる。
    var signal: Color {
        isDark ? rgb(0.125, 0.855, 0.655) : rgb(0.000, 0.722, 0.580)
    }

    // MARK: - Hardware(実機チューナーの筐体・計器面)

    /// 筐体は scheme に依らず常にグラファイト。実機は固有の物理色を持つため、light でも
    /// cream 背景の上に置かれた「機材」として映える。発光・面取りは increase-contrast で畳む。
    var prefersGlow: Bool { !highContrast }

    /// 筐体(faceplate)のブラッシュド・グラファイト。上=やや明、下=暗で立体に。
    var faceTop: Color { rgb(0.168, 0.176, 0.196) }
    var faceBottom: Color { rgb(0.086, 0.094, 0.110) }
    /// 筐体外周の面取り(上=ハイライト / 下=陰)。
    var bezelHighlight: Color { Color.white.opacity(highContrast ? 0.10 : 0.16) }
    var bezelShadow: Color { Color.black.opacity(0.55) }
    /// 筐体に沈む計器窓(recessed)のグラデーション。
    var meterFaceTop: Color { rgb(0.071, 0.078, 0.094) }
    var meterFaceBottom: Color { rgb(0.118, 0.129, 0.149) }

    /// 計器面の弧(rim、etched)。
    var meterRim: Color { Color.white.opacity(highContrast ? 0.55 : 0.28) }
    /// 目盛り(major=濃 / minor=淡)。
    var tickMajor: Color { Color.white.opacity(highContrast ? 0.95 : 0.62) }
    var tickMinor: Color { Color.white.opacity(highContrast ? 0.55 : 0.32) }

    /// 針(検出時 = bone white / 休止時 = 減光)。in-tune では signal に置換される。
    var needle: Color { highContrast ? rgb(0.992, 0.988, 0.976) : rgb(0.922, 0.902, 0.863) }
    var needleIdle: Color { rgb(0.380, 0.404, 0.439) }

    /// LED: 消灯 = 沈んだドット / 方向(♭♯)点灯 = 温かい amber / in-tune は signal を使う。
    var ledOff: Color { rgb(0.231, 0.243, 0.275) }
    var ledAmber: Color { rgb(0.965, 0.620, 0.227) }

    /// 筐体上の二次テキスト(ブランド刻印・REF ラベル)。dark 筐体専用なので scheme 非依存。
    var faceMuted: Color { highContrast ? rgb(0.769, 0.788, 0.824) : rgb(0.604, 0.627, 0.671) }

    /// 筐体角のネジ(さりげなく)。
    var screw: Color { rgb(0.306, 0.318, 0.353) }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

extension View {
    /// 現在の `colorScheme` から解決した `ToneTheme` を渡す。
    func toneTheme(_ scheme: ColorScheme) -> ToneTheme { ToneTheme(scheme: scheme) }
}

/// 音名の表示形(♯ は U+266F のシャープ記号)。VoiceOver 用の読みは `TunerCopy` 側。
extension NoteName {
    var displayText: String {
        switch self {
        case .C: return "C"
        case .Csharp: return "C\u{266F}"
        case .D: return "D"
        case .Dsharp: return "D\u{266F}"
        case .E: return "E"
        case .F: return "F"
        case .Fsharp: return "F\u{266F}"
        case .G: return "G"
        case .Gsharp: return "G\u{266F}"
        case .A: return "A"
        case .Asharp: return "A\u{266F}"
        case .B: return "B"
        }
    }
}
