import SwiftUI

/// シグネチャ要素: 実機チューナーのアナログ針メーター。
/// 下端中央を支点に、cents に比例して針が左右へ振れ、中央(0 cents)で正立 = in-tune。
/// ±50 cents を ±50° のスイープへ写像し(1 cent ≒ 1°)、目盛りは計器面に etch されたように描く。
/// 情報は音名ラベル側が読み上げるため、この図形は VoiceOver から隠す。
struct NeedleGauge: View {
    /// 表示する cents。`nil` は無音(検出なし)= 針は中央で休止・減光。
    let cents: Int?
    let inTune: Bool
    let theme: ToneTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// 片側スイープ角(度)。±50 cents ↔ ±50°。
    private let spanDeg: Double = 50

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // 支点は下端中央のやや下。針を長く取り、計器らしい弧長を確保する。
            let pivot = CGPoint(x: w / 2, y: h - 6)
            let radius = min(w * 0.56, h - 14)
            let hasReading = cents != nil
            let clamped = Double(min(max(cents ?? 0, -50), 50))
            let glow = inTune && theme.prefersGlow && !reduceTransparency

            ZStack {
                // 計器面の弧(rim)と目盛り
                Canvas { ctx, _ in
                    drawArc(ctx, pivot: pivot, radius: radius)
                    drawTicks(ctx, pivot: pivot, radius: radius)
                    drawSweetSpot(ctx, pivot: pivot, radius: radius)
                }

                // 針(支点から弧へ伸びる細いポインタ + 反対側のカウンターウェイト + ハブ)
                Needle(
                    angle: .degrees(clamped / 50 * spanDeg),
                    pivot: pivot,
                    radius: radius,
                    color: needleColor(hasReading: hasReading),
                    glow: glow,
                    glowColor: theme.signal
                )
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: clamped)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: inTune)
            }
        }
        .frame(height: 196)
        .accessibilityHidden(true)
    }

    private func needleColor(hasReading: Bool) -> Color {
        if !hasReading { return theme.needleIdle }   // 休止: 減光して in-tune と区別
        return inTune ? theme.signal : theme.needle
    }

    // MARK: - Canvas drawing

    /// 角度(度, 0 = 正立 / + = 右=シャープ)→ 弧上の点。
    private func point(_ deg: Double, pivot: CGPoint, radius: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: pivot.x + sin(a) * radius, y: pivot.y - cos(a) * radius)
    }

    private func drawArc(_ ctx: GraphicsContext, pivot: CGPoint, radius: Double) {
        var path = Path()
        path.addArc(
            center: pivot,
            radius: radius,
            startAngle: .degrees(-90 - spanDeg),
            endAngle: .degrees(-90 + spanDeg),
            clockwise: false
        )
        ctx.stroke(path, with: .color(theme.meterRim), lineWidth: 1)
    }

    /// 目盛り: -50…50 を 5 刻み。±25 / 0 を major(長く濃く)、他を minor。
    private func drawTicks(_ ctx: GraphicsContext, pivot: CGPoint, radius: Double) {
        for c in stride(from: -50.0, through: 50.0, by: 5.0) {
            let deg = c / 50 * spanDeg
            let isMajor = Int(c) % 25 == 0
            let inner = radius - (isMajor ? 18 : 10)
            let p1 = point(deg, pivot: pivot, radius: inner)
            let p2 = point(deg, pivot: pivot, radius: radius)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            let color = isMajor ? theme.tickMajor : theme.tickMinor
            ctx.stroke(path, with: .color(color), lineWidth: isMajor ? 1.6 : 1)
        }
    }

    /// 中央の許容帯(±3 cents 相当)を弧の帯で淡く示す。in-tune で signal に灯る。
    private func drawSweetSpot(_ ctx: GraphicsContext, pivot: CGPoint, radius: Double) {
        var band = Path()
        band.addArc(
            center: pivot,
            radius: radius - 2,
            startAngle: .degrees(-90 - 3),
            endAngle: .degrees(-90 + 3),
            clockwise: false
        )
        let color = inTune ? theme.signal : theme.tickMinor
        ctx.stroke(band, with: .color(color.opacity(inTune ? 0.95 : 0.55)), lineWidth: 3)
    }
}

/// 針本体。支点を中心に回転する細いポインタ。in-tune で emissive bloom を纏う。
private struct Needle: View {
    let angle: Angle
    let pivot: CGPoint
    let radius: Double
    let color: Color
    let glow: Bool
    let glowColor: Color

    var body: some View {
        Canvas { ctx, _ in
            let len = radius * 0.9
            let tail = radius * 0.16           // カウンターウェイト側の短い尾
            let tip = CGPoint(x: pivot.x, y: pivot.y - len)
            let back = CGPoint(x: pivot.x, y: pivot.y + tail)

            var shaft = Path()
            shaft.move(to: back)
            shaft.addLine(to: tip)

            // 支点を中心に回転
            var ctx2 = ctx
            ctx2.translateBy(x: pivot.x, y: pivot.y)
            ctx2.rotate(by: angle)
            ctx2.translateBy(x: -pivot.x, y: -pivot.y)

            if glow {
                ctx2.drawLayer { layer in
                    layer.addFilter(.shadow(color: glowColor.opacity(0.7), radius: 7))
                    layer.stroke(shaft, with: .color(color),
                                 style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            } else {
                ctx2.stroke(shaft, with: .color(color),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            // ハブ(支点のキャップ)
            let hub = Path(ellipseIn: CGRect(x: pivot.x - 7, y: pivot.y - 7, width: 14, height: 14))
            ctx.fill(hub, with: .color(color))
            ctx.stroke(hub, with: .color(.black.opacity(0.25)), lineWidth: 1)
        }
    }
}
