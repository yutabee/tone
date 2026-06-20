// Reproducible App Store icon generator for Tone.
// Renders the "locked" signature: a glowing emerald-teal indicator at the center
// of a faint cents ruler on dark glass. Full-bleed 1024×1024, opaque (no alpha,
// as required by the App Store), iOS applies the superellipse mask itself.
//
// Usage: swift Tools/GenerateAppIcon.swift <output.png>

import Foundation
import CoreGraphics
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

let emerald = rgba(0.125, 0.855, 0.655)        // signal (in-tune accent)
let cx = S / 2, cy = S / 2

// 1. Dark glass background — vertical gradient (CG origin is bottom-left).
let bg = CGGradient(colorsSpace: cs,
    colors: [rgba(0.086, 0.090, 0.118), rgba(0.024, 0.027, 0.047)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// 2. Emerald bloom behind the center — the light the glass refracts.
let bloom = CGGradient(colorsSpace: cs,
    colors: [rgba(0.125, 0.855, 0.655, 0.34), rgba(0.125, 0.855, 0.655, 0.0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(bloom,
    startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
    endCenter: CGPoint(x: cx, y: cy), endRadius: S * 0.46, options: [])

// 3. Faint cents ruler — vertical tick marks along the center line, fading to the edges.
let tickCount = 21
let span = S * 0.62
let left = cx - span / 2
let step = span / CGFloat(tickCount - 1)
for i in 0..<tickCount {
    let x = left + CGFloat(i) * step
    if abs(x - cx) < 34 { continue }                 // leave room for the indicator
    let isMajor = (i % 5 == 0)
    let h: CGFloat = isMajor ? 96 : 52
    let w: CGFloat = isMajor ? 6 : 4
    let dist = abs(CGFloat(i) - CGFloat(tickCount - 1) / 2) / (CGFloat(tickCount - 1) / 2)
    let alpha = 0.10 + 0.16 * (1 - dist)
    ctx.setFillColor(rgba(1, 1, 1, Double(alpha)))
    let rect = CGRect(x: x - w / 2, y: cy - h / 2, width: w, height: h)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
    ctx.fillPath()
}

// 4. Center indicator — the locked emerald bar, with an emissive bloom.
let barW: CGFloat = 44, barH: CGFloat = 300
let barRect = CGRect(x: cx - barW / 2, y: cy - barH / 2, width: barW, height: barH)
let barPath = CGPath(roundedRect: barRect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 90, color: rgba(0.125, 0.855, 0.655, 0.9))
ctx.setFillColor(emerald)
ctx.addPath(barPath); ctx.fillPath()
ctx.restoreGState()

ctx.setFillColor(emerald)                            // crisp core over the glow
ctx.addPath(barPath); ctx.fillPath()

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
