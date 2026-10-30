// Renders the MeloDock app icon ("island capsule") into AppIcon.appiconset,
// plus the matching menu bar template image into StatusBarIcon.imageset.
// Usage: swift tools/generate-app-icon.swift
//
// Everything is drawn in a 100-unit design space mapped onto the icon body,
// so every PNG is rendered sharp at its own pixel size instead of downscaled.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../MeloDock/MeloDock/Assets.xcassets/AppIcon.appiconset")
    .standardizedFileURL

// Filenames must match AppIcon.appiconset/Contents.json.
let outputs: [(name: String, pixels: Int)] = [
    ("icon_16x16@1x.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32@1x.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128@1x.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256@1x.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512@1x.png", 512), ("icon_512x512@2x.png", 1024),
]

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    )!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

/// Superellipse (|x|^n + |y|^n = 1), close to Apple's continuous-corner icon shape.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func pill(_ rect: CGRect, radius: CGFloat? = nil) -> CGPath {
    let r = radius ?? min(rect.width, rect.height) / 2
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

func drawIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let px = size / 1024  // one pixel of the 1024 template
    let simplified = pixels <= 32

    // Flip to a top-left origin, then map the 824 pt body (inset 100) to 0...100 units.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    let body = CGRect(x: 100 * px, y: 100 * px, width: 824 * px, height: 824 * px)
    let bodyPath = squircle(in: body)

    // Drop shadow inside the transparent margin (offset is in unflipped space).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * px), blur: 20 * px, color: color(0x000000, alpha: 0.3))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x6E5BFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0, color(0x6E5BFF)), (0.55, color(0xFF4F8B)), (1, color(0xFFA23D))]),
        start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: []
    )
    ctx.drawLinearGradient(
        gradient([(0, color(0xFFFFFF, alpha: 0.18)), (1, color(0xFFFFFF, alpha: 0))]),
        start: CGPoint(x: body.midX, y: body.minY), end: CGPoint(x: body.midX, y: body.midY), options: []
    )

    ctx.translateBy(x: body.minX, y: body.minY)
    ctx.scaleBy(x: body.width / 100, y: body.height / 100)

    // Island capsule.
    let capsule = pill(CGRect(x: 12, y: 37, width: 76, height: 26))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * px), blur: 24 * px, color: color(0x2A0A3A, alpha: 0.35))
    ctx.addPath(capsule)
    ctx.setFillColor(color(0x0B0B0F))
    ctx.fillPath()
    ctx.restoreGState()
    if !simplified {
        ctx.addPath(pill(CGRect(x: 12.5, y: 37.5, width: 75, height: 25)))
        ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.08))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    // Artwork tile.
    let art = CGRect(x: 17, y: 41.5, width: 17, height: 17)
    ctx.saveGState()
    ctx.addPath(pill(art, radius: 4.5))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0, color(0xFFD36E)), (1, color(0xFF5E7E))]),
        start: CGPoint(x: art.minX, y: art.minY), end: CGPoint(x: art.maxX, y: art.maxY), options: []
    )
    ctx.restoreGState()

    // Title and artist lines, then spectrum bars (fewer and thicker when tiny).
    let bars: [CGRect]
    if simplified {
        bars = [
            CGRect(x: 50, y: 45, width: 6, height: 10),
            CGRect(x: 61, y: 41.5, width: 6, height: 17),
            CGRect(x: 72, y: 44, width: 6, height: 12),
        ]
    } else {
        ctx.addPath(pill(CGRect(x: 38, y: 44.5, width: 20, height: 3.6)))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.addPath(pill(CGRect(x: 38, y: 51.5, width: 13, height: 3.6)))
        ctx.setFillColor(color(0xFFFFFF, alpha: 0.45))
        ctx.fillPath()
        bars = [
            CGRect(x: 64, y: 46, width: 3.4, height: 8),
            CGRect(x: 69.5, y: 42.5, width: 3.4, height: 15),
            CGRect(x: 75, y: 44.5, width: 3.4, height: 11),
            CGRect(x: 80.5, y: 47, width: 3.4, height: 6),
        ]
    }
    for bar in bars { ctx.addPath(pill(bar)) }
    ctx.setFillColor(color(0x5EE7FF))
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

/// Menu bar template image: the same capsule as one black shape with the
/// artwork tile and spectrum bars knocked out, on a 22 x 16 pt canvas.
func drawStatusBarIcon(scale: Int) -> CGImage {
    let width = 22 * scale, height = 16 * scale
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))

    ctx.addPath(pill(CGRect(x: 1, y: 3, width: 20, height: 10)))
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()

    ctx.setBlendMode(.clear)
    ctx.addPath(pill(CGRect(x: 4, y: 5, width: 6, height: 6), radius: 1.5))
    for bar in [
        CGRect(x: 11.5, y: 6, width: 1.5, height: 4),
        CGRect(x: 14, y: 5, width: 1.5, height: 6),
        CGRect(x: 16.5, y: 6.5, width: 1.5, height: 3),
    ] { ctx.addPath(pill(bar)) }
    ctx.fillPath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Failed to write \(url.path)") }
}

for output in outputs {
    writePNG(drawIcon(pixels: output.pixels), to: outputDir.appendingPathComponent(output.name))
    print("wrote \(output.name) (\(output.pixels)px)")
}

let statusBarDir = outputDir.deletingLastPathComponent().appendingPathComponent("StatusBarIcon.imageset")
for scale in [1, 2] {
    let name = "statusbar@\(scale)x.png"
    writePNG(drawStatusBarIcon(scale: scale), to: statusBarDir.appendingPathComponent(name))
    print("wrote \(name)")
}
