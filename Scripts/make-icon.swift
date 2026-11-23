#!/usr/bin/env swift
//
//  make-icon.swift — generates Nocta's app icon.
//
//  The icon is drawn, not painted: every shape is defined here in a 1024pt design space and
//  rendered natively at each size, so the 16pt menu-bar-adjacent sizes are as crisp as the
//  1024pt one instead of being a downscale of it.
//
//  Usage:  swift Scripts/make-icon.swift <concept> <out-dir>
//          concept ∈ crescent | ripple | card
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Design space

let D: CGFloat = 1024            // design canvas
let plate: CGFloat = 824         // Apple's icon plate inside that canvas
let plateOrigin = (D - plate) / 2

// MARK: - Colour

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

let space = CGColorSpaceCreateDeviceRGB()

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space,
               colors: stops.map { $0.0 } as CFArray,
               locations: stops.map { $0.1 })!
}

// MARK: - Geometry

/// Apple-style squircle. A superellipse is a closer match to the macOS plate than a
/// rounded rect: the curvature is continuous, so the corners never show the tangent seam
/// a circular arc leaves at 512pt and above.
func squircle(size: CGFloat, origin: CGFloat, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = size / 2, c = origin + a
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = c + a * copysign(pow(abs(ct), 2 / n), ct)
        let y = c + a * copysign(pow(abs(st), 2 / n), st)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

/// A crescent: circle 1 with circle 2 bitten out of it, expressed as two real arcs so it
/// can be filled with a gradient and reused as a clip.
///   r1: outer radius, d: centre offset, t: thickness at the waist.
struct Crescent {
    let c1: CGPoint, r1: CGFloat, c2: CGPoint, r2: CGFloat
    let hornOuter: CGFloat, hornInner: CGFloat

    init(centre: CGPoint, r1: CGFloat, offset d: CGFloat, thickness t: CGFloat) {
        self.c1 = centre
        self.r1 = r1
        self.c2 = CGPoint(x: centre.x + d, y: centre.y)
        self.r2 = r1 + d - t
        // Horn = the two circles' intersection, in each circle's own angular frame.
        let x = (d * d - r2 * r2 + r1 * r1) / (2 * d)
        let y = sqrt(max(0, r1 * r1 - x * x))
        self.hornOuter = atan2(y, x)
        self.hornInner = atan2(y, x - d)
    }

    var path: CGPath {
        let p = CGMutablePath()
        p.addArc(center: c1, radius: r1, startAngle: hornOuter, endAngle: -hornOuter, clockwise: false)
        p.addArc(center: c2, radius: r2, startAngle: -hornInner, endAngle: hornInner, clockwise: true)
        p.closeSubpath()
        return p
    }

    /// Tight bounding box of the filled crescent, for optical centring.
    var bounds: CGRect {
        CGRect(x: c1.x - r1, y: c1.y - r1,
               width: r1 + r1 * cos(hornOuter), height: r1 * 2)
    }
}

/// Polygon with rounded corners — used for the play triangle, whose sharp points would
/// otherwise alias badly at 16pt and read as a spike rather than a glyph.
func roundedPolygon(_ pts: [CGPoint], radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let n = pts.count
    // Start at the midpoint of the first edge so the first arc has a current point.
    let start = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
    p.move(to: start)
    for i in 1...n {
        let corner = pts[i % n]
        let next = pts[(i + 1) % n]
        p.addArc(tangent1End: corner, tangent2End: next, radius: radius)
    }
    p.closeSubpath()
    return p
}

func playTriangle(centre: CGPoint, width w: CGFloat, height h: CGFloat, radius: CGFloat) -> CGPath {
    // Optically centred: a triangle's visual centre sits behind its geometric one.
    let x0 = centre.x - w * 0.42, x1 = centre.x + w * 0.58
    return roundedPolygon([CGPoint(x: x0, y: centre.y + h / 2),
                           CGPoint(x: x1, y: centre.y),
                           CGPoint(x: x0, y: centre.y - h / 2)], radius: radius)
}

// MARK: - Plate

/// The night-sky plate every concept sits on: a deep vertical gradient, an indigo bloom
/// low-left where the moon light comes from, and a hairline rim so the icon keeps an edge
/// against a dark Dock.
func drawPlate(_ ctx: CGContext, bloomAt bloom: CGPoint) {
    let plateRect = CGRect(x: plateOrigin, y: plateOrigin, width: plate, height: plate)
    let shape = squircle(size: plate, origin: plateOrigin)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x000000, 0.42))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x0B0F26))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    ctx.drawLinearGradient(gradient([(rgb(0x293273), 0), (rgb(0x111737), 0.52), (rgb(0x05070F), 1)]),
                           start: CGPoint(x: plateRect.midX, y: plateRect.maxY),
                           end: CGPoint(x: plateRect.midX, y: plateRect.minY),
                           options: [])

    ctx.setBlendMode(.plusLighter)
    ctx.drawRadialGradient(gradient([(rgb(0x5B6BFF, 0.42), 0), (rgb(0x4759E8, 0.12), 0.5), (rgb(0x000000, 0), 1)]),
                           startCenter: bloom, startRadius: 0,
                           endCenter: bloom, endRadius: plate * 0.58, options: [])
    ctx.setBlendMode(.normal)

    // Inner top highlight — the glass lip.
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.20))
    ctx.setLineWidth(5)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Concepts

/// Crescent moon cradling a play triangle. The product in two shapes: night, and playback.
func drawCrescent(_ ctx: CGContext) {
    drawPlate(ctx, bloomAt: CGPoint(x: D * 0.34, y: D * 0.30))

    let moon = Crescent(centre: .zero, r1: 268, offset: 98, thickness: 110)
    let tri = playTriangle(centre: CGPoint(x: 48, y: 0), width: 164, height: 184, radius: 20)
    let markBounds = moon.bounds.union(tri.boundingBoxOfPath)
    let scale: CGFloat = 0.90

    ctx.saveGState()
    ctx.translateBy(x: D / 2, y: D / 2)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -markBounds.midX, y: -markBounds.midY)

    // Moon: lit from the lower left, so the gradient runs across the crescent, not down it.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: rgb(0x8CA0FF, 0.42))
    ctx.addPath(moon.path)
    ctx.setFillColor(rgb(0xF4F6FF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(moon.path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(rgb(0xFFFFFF), 0), (rgb(0xE7ECFF), 0.45), (rgb(0xB9C6FF), 1)]),
                           start: CGPoint(x: moon.bounds.minX, y: moon.bounds.maxY),
                           end: CGPoint(x: moon.bounds.maxX, y: moon.bounds.minY), options: [])
    ctx.restoreGState()

    // Play triangle, one step back from the moon so the two read as foreground and light.
    ctx.saveGState()
    ctx.addPath(tri)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(rgb(0xFFFFFF, 0.97), 0), (rgb(0xA9B8FF, 0.95), 1)]),
                           start: CGPoint(x: tri.boundingBoxOfPath.minX, y: tri.boundingBoxOfPath.maxY),
                           end: CGPoint(x: tri.boundingBoxOfPath.maxX, y: tri.boundingBoxOfPath.minY),
                           options: [])
    ctx.restoreGState()

    ctx.restoreGState()
}

/// Crescent moon with its light rippling outward — moonlight and sound waves as one shape.
func drawRipple(_ ctx: CGContext) {
    drawPlate(ctx, bloomAt: CGPoint(x: D * 0.36, y: D * 0.32))

    let moon = Crescent(centre: .zero, r1: 248, offset: 64, thickness: 96)
    let waves: [(CGFloat, CGFloat, CGFloat)] = [(158, 40, 0.80), (268, 34, 0.38)]  // radius, width, alpha
    var markBounds = moon.bounds
    for (r, w, _) in waves {
        markBounds = markBounds.union(CGRect(x: moon.c2.x - r - w, y: -r - w, width: (r + w) * 2, height: (r + w) * 2))
    }

    ctx.saveGState()
    ctx.translateBy(x: D / 2, y: D / 2)
    ctx.scaleBy(x: 0.84, y: 0.84)
    ctx.translateBy(x: -markBounds.midX, y: -markBounds.midY)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 44, color: rgb(0x8CA0FF, 0.5))
    ctx.addPath(moon.path)
    ctx.setFillColor(rgb(0xF4F6FF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(moon.path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(rgb(0xFFFFFF), 0), (rgb(0xC3CFFF), 1)]),
                           start: CGPoint(x: moon.bounds.minX, y: moon.bounds.maxY),
                           end: CGPoint(x: moon.bounds.maxX, y: moon.bounds.minY), options: [])
    ctx.restoreGState()

    ctx.setLineCap(.round)
    for (r, w, a) in waves {
        ctx.addArc(center: moon.c2, radius: r, startAngle: -.pi / 4.6, endAngle: .pi / 4.6, clockwise: false)
        ctx.setStrokeColor(rgb(0xD8DFFF, a))
        ctx.setLineWidth(w)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

/// The product, literally: one Liquid Glass card floating on the Lock Screen at night.
func drawCard(_ ctx: CGContext) {
    drawPlate(ctx, bloomAt: CGPoint(x: D * 0.5, y: D * 0.34))

    let card = CGRect(x: 196, y: 372, width: 632, height: 280)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 84, cornerHeight: 84, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: rgb(0x000000, 0.5))
    ctx.addPath(cardPath)
    ctx.setFillColor(rgb(0xFFFFFF, 0.16))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(rgb(0xFFFFFF, 0.34), 0), (rgb(0xFFFFFF, 0.08), 1)]),
                           start: CGPoint(x: card.midX, y: card.maxY),
                           end: CGPoint(x: card.midX, y: card.minY), options: [])
    ctx.addPath(cardPath)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.5))
    ctx.setLineWidth(7)
    ctx.strokePath()
    ctx.restoreGState()

    // Artwork tile.
    let art = CGRect(x: 246, y: 422, width: 180, height: 180)
    let artPath = CGPath(roundedRect: art, cornerWidth: 48, cornerHeight: 48, transform: nil)
    ctx.saveGState()
    ctx.addPath(artPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(rgb(0x8E7CFF), 0), (rgb(0x4759E8), 1)]),
                           start: CGPoint(x: art.minX, y: art.maxY),
                           end: CGPoint(x: art.maxX, y: art.minY), options: [])
    ctx.restoreGState()

    // A crescent sits in the artwork tile, so the mark still carries the name.
    let moon = Crescent(centre: CGPoint(x: art.midX, y: art.midY), r1: 62, offset: 20, thickness: 26)
    ctx.addPath(moon.path)
    ctx.setFillColor(rgb(0xFFFFFF, 0.95))
    ctx.fillPath()

    // Play glyph + progress rail.
    ctx.addPath(playTriangle(centre: CGPoint(x: 520, y: 540), width: 92, height: 100, radius: 12))
    ctx.setFillColor(rgb(0xFFFFFF, 0.97))
    ctx.fillPath()

    ctx.setLineCap(.round)
    ctx.setLineWidth(22)
    ctx.move(to: CGPoint(x: 480, y: 452)); ctx.addLine(to: CGPoint(x: 762, y: 452))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.28)); ctx.strokePath()
    ctx.move(to: CGPoint(x: 480, y: 452)); ctx.addLine(to: CGPoint(x: 630, y: 452))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.95)); ctx.strokePath()
}

// MARK: - Render

let concepts: [String: (CGContext) -> Void] = [
    "crescent": drawCrescent, "ripple": drawRipple, "card": drawCard,
]

let args = CommandLine.arguments
let name = args.count > 1 ? args[1] : "crescent"
let outDir = args.count > 2 ? args[2] : "."
guard let draw = concepts[name] else {
    FileHandle.standardError.write("unknown concept '\(name)' — use \(concepts.keys.sorted().joined(separator: " | "))\n".data(using: .utf8)!)
    exit(1)
}

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    let s = CGFloat(px) / D
    ctx.scaleBy(x: s, y: s)
    draw(ctx)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// The .iconset layout iconutil expects.
let iconset: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, file) in iconset {
    write(render(px), to: "\(outDir)/\(file).png")
}
print("wrote \(iconset.count) sizes for '\(name)' to \(outDir)")
