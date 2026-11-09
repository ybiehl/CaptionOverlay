// draw-icon.swift: renders the CaptionOverlay app icon at every .iconset
// size. Run by Scripts/make-icon.sh; this file is the single source of
// truth for the artwork.
//
//   swift draw-icon.swift <output-dir>
//
// Same plate as DisplayBridge's icon (values copied from its
// draw-icon.swift): 824 px rounded rect on a 1024 canvas, blue gradient
// #6FC6FC to #1D6FEA, white glyph with one soft shadow. The glyph is a
// caption box with two lines of "words", the lower line shorter.
// Geometry is in a 240 x 240 space.

import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func drawIcon(canvas: CGFloat, into ctx: CGContext) {
    // Flip to a top-left origin.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    let plate = canvas * 824.0 / 1024.0
    let margin = (canvas - plate) / 2
    let plateRect = CGRect(x: margin, y: margin, width: plate, height: plate)
    let corner = plate * 185.4 / 824.0

    ctx.addPath(CGPath(roundedRect: plateRect, cornerWidth: corner,
                       cornerHeight: corner, transform: nil))
    ctx.clip()
    let colors = [
        CGColor(red: 0x6F / 255.0, green: 0xC6 / 255.0, blue: 0xFC / 255.0, alpha: 1),
        CGColor(red: 0x1D / 255.0, green: 0x6F / 255.0, blue: 0xEA / 255.0, alpha: 1),
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvas / 2, y: plateRect.minY),
        end: CGPoint(x: canvas / 2, y: plateRect.maxY),
        options: [])

    // Map the 240 space (content box 8...232) onto the plate, then pull
    // the glyph in to 82 % around the centre for the icon safe area.
    let scale = plate / 224.0
    ctx.translateBy(x: margin - 8 * scale, y: margin - 8 * scale)
    ctx.scaleBy(x: scale, y: scale)
    let glyphScale: CGFloat = 0.82
    ctx.translateBy(x: 120, y: 120)
    ctx.scaleBy(x: glyphScale, y: glyphScale)
    ctx.translateBy(x: -120, y: -120)

    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.018),
                  blur: canvas * 0.05,
                  color: CGColor(gray: 0, alpha: 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    defer { ctx.endTransparencyLayer() }

    let white = CGColor(gray: 1, alpha: 1)
    ctx.setStrokeColor(white)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Caption box.
    ctx.setLineWidth(9)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 26, y: 58, width: 188, height: 124),
                       cornerWidth: 24, cornerHeight: 24, transform: nil))
    ctx.strokePath()

    // Two lines of words.
    ctx.setLineWidth(13)
    let words: [(CGFloat, CGFloat, CGFloat)] = [
        (60, 118, 102), (140, 180, 102),   // upper line
        (60, 96, 138), (118, 152, 138),    // lower line, shorter
    ]
    for (from, to, y) in words {
        ctx.move(to: CGPoint(x: from, y: y))
        ctx.addLine(to: CGPoint(x: to, y: y))
        ctx.strokePath()
    }
}

func writePNG(size: Int, scale: Int, name: String) {
    let pixels = size * scale
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context for \(name)") }
    ctx.interpolationQuality = .high
    drawIcon(canvas: CGFloat(pixels), into: ctx)
    guard let image = ctx.makeImage() else { fatalError("no image for \(name)") }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) else { fatalError("no destination for \(name)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed: \(name)") }
}

for size in [16, 32, 128, 256, 512] {
    writePNG(size: size, scale: 1, name: "icon_\(size)x\(size).png")
    writePNG(size: size, scale: 2, name: "icon_\(size)x\(size)@2x.png")
}
print("iconset rendered to \(outputDir)")
