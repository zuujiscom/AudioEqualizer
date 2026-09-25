// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreGraphics

// Renders the app icon: vertical EQ faders on a gradient squircle.
// Drawn in a 1024pt design space and rendered natively at each output size,
// so nothing is upscaled. 16/32pt fall back to a bolder three-bar mark, since
// fader caps are illegible that small.
//
// Regenerate after editing:
//   swift Tools/makeicon.swift AudioEqualizer/Resources/Assets.xcassets/AppIcon.appiconset
//
// Not part of the app target — it has top-level code and builds standalone.

let outDir = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [r, g, b, a])!
}

let faderColors = [
    color(0.30, 0.87, 0.52),   // green   – lows
    color(0.24, 0.80, 0.82),   // teal
    color(0.99, 0.80, 0.26),   // yellow
    color(0.99, 0.44, 0.36),   // red     – highs
]

// Knob heights as a fraction of the track: a gentle EQ curve.
let knobPositions: [CGFloat] = [0.80, 0.40, 0.58, 0.88]

func render(size: Int) -> CGImage? {
    let scale = CGFloat(size) / 1024.0
    func p(_ v: CGFloat) -> CGFloat { v * scale }

    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: 824pt rounded square centred in a 1024pt canvas.
    let margin: CGFloat = 100
    let side: CGFloat = 1024 - margin * 2
    let plate = CGRect(x: p(margin), y: p(margin), width: p(side), height: p(side))
    let platePath = CGPath(roundedRect: plate, cornerWidth: p(185), cornerHeight: p(185), transform: nil)

    // Drop shadow under the plate.
    if size >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -p(14)), blur: p(30),
                      color: color(0, 0, 0, 0.40))
        ctx.addPath(platePath)
        ctx.setFillColor(color(0, 0, 0, 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Plate gradient.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: srgb, colors: [
        color(0.22, 0.29, 0.55),
        color(0.07, 0.09, 0.19),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: plate.midX, y: plate.maxY),
                           end: CGPoint(x: plate.midX, y: plate.minY), options: [])

    // Soft highlight along the top edge.
    let sheen = CGGradient(colorsSpace: srgb, colors: [
        color(1, 1, 1, 0.16),
        color(1, 1, 1, 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: plate.midX, y: plate.maxY),
                           end: CGPoint(x: plate.midX, y: plate.midY), options: [])
    ctx.restoreGState()

    // At 16/32pt the faders turn to mush, so draw a bolder simplified mark.
    let simplified = size <= 32
    let count = simplified ? 3 : 4
    let areaX: CGFloat = simplified ? 246 : 262
    let areaW: CGFloat = simplified ? 532 : 500
    let trackBottom: CGFloat = simplified ? 286 : 300
    let trackTop: CGFloat = simplified ? 738 : 724
    let trackW: CGFloat = simplified ? 124 : 46

    let columnW = areaW / CGFloat(count)

    for index in 0..<count {
        let centerX = areaX + columnW * (CGFloat(index) + 0.5)
        let tint = faderColors[simplified ? index * 4 / 3 : index]
        let fraction = simplified ? [0.52, 1.0, 0.74][index] : knobPositions[index]
        let knobY = trackBottom + (trackTop - trackBottom) * fraction

        if simplified {
            // Plain bars: legible at 16pt.
            let bar = CGRect(x: p(centerX - trackW / 2), y: p(trackBottom),
                             width: p(trackW), height: p(knobY - trackBottom))
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: p(trackW / 2),
                               cornerHeight: p(trackW / 2), transform: nil))
            ctx.setFillColor(tint)
            ctx.fillPath()
            continue
        }

        // Track.
        let track = CGRect(x: p(centerX - trackW / 2), y: p(trackBottom),
                           width: p(trackW), height: p(trackTop - trackBottom))
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: p(trackW / 2),
                           cornerHeight: p(trackW / 2), transform: nil))
        ctx.setFillColor(color(1, 1, 1, 0.18))
        ctx.fillPath()

        // Filled portion up to the knob.
        let filled = CGRect(x: p(centerX - trackW / 2), y: p(trackBottom),
                            width: p(trackW), height: p(knobY - trackBottom))
        ctx.addPath(CGPath(roundedRect: filled, cornerWidth: p(trackW / 2),
                           cornerHeight: p(trackW / 2), transform: nil))
        ctx.setFillColor(tint)
        ctx.fillPath()

        // Fader cap.
        let knobW: CGFloat = 108
        let knobH: CGFloat = 58
        let knob = CGRect(x: p(centerX - knobW / 2), y: p(knobY - knobH / 2),
                          width: p(knobW), height: p(knobH))
        let knobPath = CGPath(roundedRect: knob, cornerWidth: p(20), cornerHeight: p(20), transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -p(6)), blur: p(14), color: color(0, 0, 0, 0.5))
        ctx.addPath(knobPath)
        ctx.setFillColor(color(0.97, 0.98, 1.0, 1))
        ctx.fillPath()
        ctx.restoreGState()

        // Grip line across the cap.
        let grip = CGRect(x: p(centerX - knobW / 2 + 22), y: p(knobY - 3),
                          width: p(knobW - 44), height: p(6))
        ctx.addPath(CGPath(roundedRect: grip, cornerWidth: p(3), cornerHeight: p(3), transform: nil))
        ctx.setFillColor(color(0.55, 0.60, 0.72, 1))
        ctx.fillPath()
    }

    return ctx.makeImage()
}

for size in sizes {
    guard let image = render(size: size) else {
        FileHandle.standardError.write("failed to render \(size)\n".data(using: .utf8)!)
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(size).png")
    try! data.write(to: url)
    print("wrote \(url.lastPathComponent)")
}
