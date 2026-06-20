import SwiftUI
import ToneCore

/// スイス派ミニマルの視覚トークン。monochrome ink/paper + 単一の signal(in-tune)アクセント。
/// 配色は light/dark に適応する(`colorScheme` から解決)。
struct ToneTheme {
    let scheme: ColorScheme

    /// 背景(紙)。
    var paper: Color {
        scheme == .dark ? Color(red: 0.051, green: 0.051, blue: 0.059)
                        : Color(red: 0.961, green: 0.961, blue: 0.949)
    }
    /// 主要素(音名・indicator)。
    var ink: Color {
        scheme == .dark ? Color(red: 0.929, green: 0.929, blue: 0.918)
                        : Color(red: 0.102, green: 0.102, blue: 0.118)
    }
    /// 二次情報(ラベル・cents 数値)。
    var muted: Color {
        scheme == .dark ? Color(red: 0.541, green: 0.541, blue: 0.557)
                        : Color(red: 0.482, green: 0.482, blue: 0.471)
    }
    /// 目盛りの細線。
    var faint: Color {
        scheme == .dark ? Color(red: 0.231, green: 0.231, blue: 0.247)
                        : Color(red: 0.812, green: 0.812, blue: 0.796)
    }
    /// in-tune のときだけ現れる単一アクセント(emerald-teal、acid green を避ける)。
    var signal: Color {
        scheme == .dark ? Color(red: 0.114, green: 0.820, blue: 0.631)
                        : Color(red: 0.000, green: 0.722, blue: 0.580)
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
