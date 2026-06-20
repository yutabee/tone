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
