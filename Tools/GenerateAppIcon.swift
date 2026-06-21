// Reproducible App Store icon generator for Tone.
// Renders the app's own Tuner UI as the icon: a recessed graphite meter window
// with the analog needle locked at 0 cents (the in-tune signature) and the "A4"
// note — the standard reference pitch — read out above it. Tokens mirror the
// runtime ToneTheme / NeedleGauge / lcdReadout so the icon and the live screen
// share one visual language.
//
// Full-bleed 1024×1024, opaque (no alpha, as required by the App Store); iOS
// applies the superellipse mask itself.
//
// Usage: swift Tools/GenerateAppIcon.swift <output.png>

import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let pixels = 1024
let S = CGFloat(pixels)
let cs = CGColorSpaceCreateDeviceRGB()

// Opaque context (noneSkipLast → PNG without an alpha channel).
guard let ctx = CGContext(
    data: nil, width: pixels, height: pixels,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("context") }

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

// ToneTheme tokens (dark graphite faceplate, recessed meter window, emerald signal).
let faceTop = rgba(0.168, 0.176, 0.196), faceBottom = rgba(0.086, 0.094, 0.110)
let meterTop = rgba(0.071, 0.078, 0.094), meterBottom = rgba(0.118, 0.129, 0.149)
let signal = rgba(0.125, 0.855, 0.655)
let signalNS = NSColor(red: 0.125, green: 0.855, blue: 0.655, alpha: 1)        // hero note (in-tune)
let octaveNS = NSColor(red: 0.922, green: 0.902, blue: 0.863, alpha: 0.70)     // dimmer octave digit
let tickMajor = rgba(1, 1, 1, 0.62), tickMinor = rgba(1, 1, 1, 0.32), meterRim = rgba(1, 1, 1, 0.28)
let cx = S / 2

func rrect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
/// SF Rounded at a given weight, mirroring the runtime `.rounded` LCD readout.
func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? base }
    return base
}
func measure(_ s: String, _ font: NSFont) -> CGRect {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font]))
    return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
}
func drawText(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, baseline: CGFloat,
              glow: CGColor? = nil, glowBlur: CGFloat = 0) {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
    if let glow = glow {
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: glowBlur, color: glow)
        ctx.textPosition = CGPoint(x: x, y: baseline); CTLineDraw(line, ctx); ctx.restoreGState()
    }
    ctx.textPosition = CGPoint(x: x, y: baseline); CTLineDraw(line, ctx)
}

// 1. Full-bleed graphite faceplate + top sheen (CG origin is bottom-left).
let faceG = CGGradient(colorsSpace: cs, colors: [faceTop, faceBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(faceG, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
let sheen = CGGradient(colorsSpace: cs, colors: [rgba(1, 1, 1, 0.06), rgba(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: cx, y: S), startRadius: 0,
                       endCenter: CGPoint(x: cx, y: S), endRadius: S * 0.72, options: [])

// 2. Recessed meter window (graphite face, faint in-tune emerald wash + bloom, inset edge).
let inset: CGFloat = 96
let win = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let winPath = rrect(win, 120)
ctx.saveGState(); ctx.addPath(winPath); ctx.clip()
let mG = CGGradient(colorsSpace: cs, colors: [meterTop, meterBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(mG, start: CGPoint(x: 0, y: win.maxY), end: CGPoint(x: 0, y: win.minY), options: [])
ctx.setFillColor(rgba(0.125, 0.855, 0.655, 0.05)); ctx.fill(win)
let bloom = CGGradient(colorsSpace: cs,
    colors: [rgba(0.125, 0.855, 0.655, 0.16), rgba(0.125, 0.855, 0.655, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: cx, y: S * 0.36), startRadius: 0,
                       endCenter: CGPoint(x: cx, y: S * 0.36), endRadius: S * 0.28, options: [])
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(winPath); ctx.replacePathWithStrokedPath(); ctx.clip()
let insetG = CGGradient(colorsSpace: cs, colors: [rgba(0, 0, 0, 0.55), rgba(1, 1, 1, 0.06)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(insetG, start: CGPoint(x: 0, y: win.maxY), end: CGPoint(x: 0, y: win.minY), options: [])
ctx.restoreGState()

// Gauge geometry first so the note can be placed relative to the dome apex.
// A clean 180° semicircle: the needle pivots at the diameter centre and points
// straight up at 0¢. `deg` is measured from vertical (0 = up, + = right).
let center = CGPoint(x: cx, y: win.minY + 150)
let radius: CGFloat = 312
let apex = center.y + radius
func arcPoint(_ deg: Double, _ r: CGFloat) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: center.x + CGFloat(sin(a)) * r, y: center.y + CGFloat(cos(a)) * r)
}

// 3. "A4" readout — emerald note + dimmer octave (lcdReadout), centred above the dome.
let fA = roundedFont(236, .semibold)
let fOct = roundedFont(116, .medium)
let bA = measure("A", fA), bOct = measure("4", fOct)
let gap: CGFloat = 22
let totalW = bA.width + gap + bOct.width
let startX = cx - totalW / 2
let baseline = apex + 96
drawText("A", fA, signalNS, x: startX - bA.minX, baseline: baseline,
         glow: rgba(0.125, 0.855, 0.655, 0.40), glowBlur: 34)
drawText("4", fOct, octaveNS, x: startX + bA.width + gap - bOct.minX, baseline: baseline)

// 4. Semicircle gauge: 180° rim, ticks every 15° (major every 45°), lit sweet spot at apex.
ctx.setStrokeColor(meterRim); ctx.setLineWidth(5)
ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi, clockwise: false)
ctx.strokePath()
var deg = -90.0
while deg <= 90.0 {
    let major = Int(deg) % 45 == 0
    let inner = radius - (major ? 56 : 34)
    let p1 = arcPoint(deg, inner), p2 = arcPoint(deg, radius)
    ctx.setStrokeColor(major ? tickMajor : tickMinor); ctx.setLineWidth(major ? 8 : 5); ctx.setLineCap(.round)
    ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
    deg += 15
}
// sweet spot lit emerald at the apex (0¢ = in tune)
ctx.setStrokeColor(rgba(0.125, 0.855, 0.655, 0.95)); ctx.setLineWidth(15); ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius - 3,
           startAngle: .pi / 2 - 4.5 * (.pi / 180), endAngle: .pi / 2 + 4.5 * (.pi / 180), clockwise: false)
ctx.strokePath()
// needle locked vertical — emerald with emissive bloom + hub
let tip = arcPoint(0, radius * 0.86)
ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 44, color: rgba(0.125, 0.855, 0.655, 0.9))
ctx.setStrokeColor(signal); ctx.setLineWidth(18); ctx.setLineCap(.round)
ctx.move(to: center); ctx.addLine(to: tip); ctx.strokePath(); ctx.restoreGState()
ctx.setStrokeColor(signal); ctx.setLineWidth(18); ctx.setLineCap(.round)
ctx.move(to: center); ctx.addLine(to: tip); ctx.strokePath()
ctx.setFillColor(signal)
ctx.addPath(CGPath(ellipseIn: CGRect(x: center.x - 28, y: center.y - 28, width: 56, height: 56), transform: nil)); ctx.fillPath()
ctx.setFillColor(rgba(0, 0, 0, 0.30))
ctx.addPath(CGPath(ellipseIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22), transform: nil)); ctx.fillPath()

// 5. Encode PNG.
guard let image = ctx.makeImage() else { fatalError("image") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let outURL = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fatalError("destination") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("finalize") }
print("wrote \(outURL.path) (\(pixels)×\(pixels), opaque)")
