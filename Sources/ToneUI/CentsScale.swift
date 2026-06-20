import SwiftUI

/// シグネチャ要素: cents を計測する定規。中央 0、±50 までの hairline 目盛りと、
/// cents に比例して動く細い indicator。in-tune で indicator と中央 tick が signal にロックする。
/// 情報は音名ラベル側が読み上げるので、この図形は VoiceOver から隠す。
struct CentsScale: View {
    /// 表示する cents。`nil` は無音(検出なし)。
    let cents: Int?
    let inTune: Bool
    let theme: ToneTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let inset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let usable = (width - inset * 2) / 2          // 中央から片側の幅
            let midX = width / 2
            let hasReading = cents != nil
            let clamped = Double(min(max(cents ?? 0, -50), 50))
            let indicatorX = midX + CGFloat(clamped / 50) * usable
            // ロック時のみ、深い背景に対して中央 tick と indicator が発光する(dark / 標準コントラスト)。
            let glow = inTune && theme.prefersDepthEffects && !reduceTransparency

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let centerY = size.height / 2
                    // 目盛り: -50…50 を 10 刻み。中央=高/濃、±50=中、他=短/淡。
                    for tick in stride(from: -50, through: 50, by: 10) {
                        let x = midX + CGFloat(Double(tick) / 50) * usable
                        let isCenter = tick == 0
                        let isEdge = abs(tick) == 50
                        let tickHeight: CGFloat = isCenter ? size.height : (isEdge ? size.height * 0.55 : size.height * 0.34)
                        let color = isCenter ? (inTune ? theme.signal : theme.ink) : theme.faint
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: centerY - tickHeight / 2))
                        path.addLine(to: CGPoint(x: x, y: centerY + tickHeight / 2))
                        if isCenter && glow {
                            context.drawLayer { layer in
                                layer.addFilter(.shadow(color: theme.signal.opacity(0.7), radius: 6))
                                layer.stroke(path, with: .color(color), lineWidth: ToneMetrics.hairline)
                            }
                        } else {
                            context.stroke(path, with: .color(color), lineWidth: ToneMetrics.hairline)
                        }
                    }
                }

                if hasReading {
                    Capsule(style: .continuous)
                        .fill(inTune ? theme.signal : theme.ink)
                        .frame(width: ToneMetrics.indicatorWidth, height: height)
                        .shadow(color: theme.signal.opacity(glow ? 0.6 : 0), radius: glow ? 8 : 0)
                        .shadow(color: theme.signal.opacity(glow ? 0.32 : 0), radius: glow ? 16 : 0)
                        .position(x: indicatorX, y: height / 2)
                        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: clamped)
                        .animation(.easeInOut(duration: 0.18), value: inTune)
                }
            }
        }
        .frame(height: ToneMetrics.scaleHeight)
        .accessibilityHidden(true)
    }
}
