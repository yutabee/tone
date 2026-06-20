import SwiftUI
import ToneCore

/// スイス派ミニマルの視覚トークン。monochrome ink/paper + 単一の signal(in-tune)アクセント。
/// dark は「夜の計測器」を志向する: 上方からの淡い光で奥行きを与え、ロックの瞬間だけ signal が
/// 発光する。配色は `colorScheme` と `colorSchemeContrast` から解決し、increase-contrast 時は
/// 奥行き演出を畳んで純粋な可読性に倒す。
struct ToneTheme {
    let scheme: ColorScheme
    var contrast: ColorSchemeContrast = .standard

    var isDark: Bool { scheme == .dark }
    private var highContrast: Bool { contrast == .increased }

    /// dark かつ標準コントラストのときだけ奥行き演出(背景グラデーション/発光)を許可する。
    var prefersDepthEffects: Bool { isDark && !highContrast }

    // MARK: - Surfaces

    /// 背景の基準単色(capsule 文字色・フォールバックに使う)。
    var paper: Color {
        isDark ? rgb(0.055, 0.059, 0.071) : rgb(0.961, 0.961, 0.949)
    }
    /// 背景グラデーション上端。dark は上方からの淡い光、light / 高コントラストは paper と同値=フラット。
    var paperTop: Color {
        prefersDepthEffects ? rgb(0.090, 0.094, 0.110) : paper
    }
    /// 背景グラデーション下端。
    var paperBottom: Color {
        prefersDepthEffects ? rgb(0.039, 0.043, 0.055) : paper
    }

    // MARK: - Ink

    /// 主要素(音名・indicator)。dark は眩しさを避けた bone white(わずかに暖色)。
    var ink: Color {
        if isDark { return highContrast ? rgb(0.976, 0.976, 0.965) : rgb(0.914, 0.906, 0.882) }
        return highContrast ? rgb(0.039, 0.039, 0.047) : rgb(0.102, 0.102, 0.118)
    }
    /// 二次情報(ラベル・cents 数値)。
    var muted: Color {
        if isDark { return highContrast ? rgb(0.710, 0.718, 0.745) : rgb(0.553, 0.561, 0.592) }
        return highContrast ? rgb(0.353, 0.353, 0.345) : rgb(0.482, 0.482, 0.471)
    }
    /// 目盛りの細線(etched hairline)。
    var faint: Color {
        if isDark { return highContrast ? rgb(0.392, 0.404, 0.427) : rgb(0.196, 0.208, 0.227) }
        return highContrast ? rgb(0.659, 0.659, 0.643) : rgb(0.812, 0.812, 0.796)
    }

    // MARK: - Signal (in-tune)

    /// in-tune のときだけ現れる単一アクセント(emerald-teal、acid green を避ける)。
    /// dark は発光に耐えるよう僅かに luminance を上げる。
    var signal: Color {
        isDark ? rgb(0.125, 0.855, 0.655) : rgb(0.000, 0.722, 0.580)
    }

    // MARK: - Liquid Glass(材質と光)

    /// 色付き背景グラデーション。ガラスが屈折する“素地”を与える。
    var bgTop: Color { isDark ? rgb(0.082, 0.086, 0.110) : rgb(0.984, 0.980, 0.965) }
    var bgBottom: Color { isDark ? rgb(0.035, 0.039, 0.059) : rgb(0.925, 0.918, 0.902) }

    /// 背景に滲む 2 つの光(dark: teal + indigo)。ガラス面に色味の depth を映す。
    var haloPrimary: Color { isDark ? rgb(0.071, 0.624, 0.494) : rgb(0.000, 0.722, 0.580) }
    var haloSecondary: Color { isDark ? rgb(0.243, 0.255, 0.561) : rgb(0.490, 0.529, 0.961) }

    /// ガラス面の specular edge(上端=明 / 下端=暗)。
    var glassEdgeTop: Color { isDark ? Color.white.opacity(0.30) : Color.white.opacity(0.90) }
    var glassEdgeBottom: Color { isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.06) }

    /// reduce-transparency 時のガラス代替(不透明な elevated 面)。
    var solidPanel: Color { isDark ? rgb(0.110, 0.118, 0.149) : rgb(1.000, 1.000, 1.000) }

    /// パネルの落ち影(奥行き)。
    var cardShadow: Color { isDark ? Color.black.opacity(0.45) : Color.black.opacity(0.12) }

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
    var meterRim: Color { Color.white.opacity(highContrast ? 0.55 : 0.22) }
    /// 目盛り(major=濃 / minor=淡)。
    var tickMajor: Color { Color.white.opacity(highContrast ? 0.95 : 0.62) }
    var tickMinor: Color { Color.white.opacity(highContrast ? 0.55 : 0.26) }

    /// 針(検出時 = bone white / 休止時 = 減光)。in-tune では signal に置換される。
    var needle: Color { highContrast ? rgb(0.992, 0.988, 0.976) : rgb(0.922, 0.902, 0.863) }
    var needleIdle: Color { rgb(0.380, 0.404, 0.439) }

    /// LED: 消灯 = 沈んだドット / 方向(♭♯)点灯 = 温かい amber / in-tune は signal を使う。
    var ledOff: Color { rgb(0.231, 0.243, 0.275) }
    var ledAmber: Color { rgb(0.965, 0.620, 0.227) }

    /// 筐体上の二次テキスト(ブランド刻印・REF ラベル)。dark 筐体専用なので scheme 非依存。
    var faceMuted: Color { highContrast ? rgb(0.769, 0.788, 0.824) : rgb(0.553, 0.576, 0.620) }

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

/// 余白主体のレイアウト定数。
enum ToneMetrics {
    static let screenPadding: CGFloat = 28
    static let scaleHeight: CGFloat = 56
    static let hairline: CGFloat = 1
    static let indicatorWidth: CGFloat = 2
}
