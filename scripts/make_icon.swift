#!/usr/bin/env swift
// Draws the app icon (four calm lanes with cards) and writes the AppIcon set.
// Run from the repo root:  swift scripts/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let accents: [UInt32] = [0x4F6D9A, 0xD98E04, 0xB5546A, 0x3E8E63]
let cardFills: [UInt32] = [0xF4F7FB, 0xFDF8EE, 0xFBF3F5, 0xF2F8F4]
let cardsPerLane = [3, 2, 1, 2]

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = context.cgContext
    let unit = s / 1024

    // macOS icon grid: an 824 pt body centred in 1024, continuous corners.
    let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186 * unit, cornerHeight: 186 * unit, transform: nil)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 28 * unit, color: color(0x000000, 0.22))
    cg.addPath(bodyPath)
    cg.setFillColor(color(0xFFFFFF))
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(bodyPath)
    cg.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0xFDFDFE), color(0xEEF0F4)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])

    // Four lanes.
    let inset: CGFloat = 92 * unit
    let gutter: CGFloat = 26 * unit
    let laneWidth = (body.width - inset * 2 - gutter * 3) / 4
    let laneTop = body.maxY - inset
    let laneBottom = body.minY + inset
    for lane in 0..<4 {
        let x = body.minX + inset + CGFloat(lane) * (laneWidth + gutter)
        let laneRect = CGRect(x: x, y: laneBottom, width: laneWidth, height: laneTop - laneBottom)
        cg.addPath(CGPath(roundedRect: laneRect, cornerWidth: 30 * unit, cornerHeight: 30 * unit, transform: nil))
        cg.setFillColor(color(accents[lane], 0.07))
        cg.fillPath()

        // Accent bar.
        let bar = CGRect(x: x + 18 * unit, y: laneTop - 34 * unit, width: laneWidth - 36 * unit, height: 13 * unit)
        cg.addPath(CGPath(roundedRect: bar, cornerWidth: 6.5 * unit, cornerHeight: 6.5 * unit, transform: nil))
        cg.setFillColor(color(accents[lane]))
        cg.fillPath()

        // Cards.
        var cardTop = laneTop - 66 * unit
        for card in 0..<cardsPerLane[lane] {
            let height = (card == 0 ? 112 : 92) * unit
            let rect = CGRect(x: x + 14 * unit, y: cardTop - height, width: laneWidth - 28 * unit, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: 22 * unit, cornerHeight: 22 * unit, transform: nil)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -3 * unit), blur: 8 * unit, color: color(0x000000, 0.10))
            cg.addPath(path)
            cg.setFillColor(color(cardFills[lane]))
            cg.fillPath()
            cg.restoreGState()
            cg.addPath(path)
            cg.setStrokeColor(color(0x000000, 0.07))
            cg.setLineWidth(2 * unit)
            cg.strokePath()
            // A title line and a priority dot.
            let line = CGRect(x: rect.minX + 16 * unit, y: rect.maxY - 34 * unit, width: rect.width * 0.62, height: 11 * unit)
            cg.addPath(CGPath(roundedRect: line, cornerWidth: 5.5 * unit, cornerHeight: 5.5 * unit, transform: nil))
            cg.setFillColor(color(0x1D1D1F, 0.55))
            cg.fillPath()
            let dot = CGRect(x: rect.minX + 16 * unit, y: rect.minY + 16 * unit, width: 14 * unit, height: 14 * unit)
            cg.setFillColor(color(accents[lane], 0.9))
            cg.fillEllipse(in: dot)
            cardTop -= height + 16 * unit
        }
    }
    cg.restoreGState()

    // Hairline edge.
    cg.addPath(bodyPath)
    cg.setStrokeColor(color(0x000000, 0.08))
    cg.setLineWidth(2 * unit)
    cg.strokePath()

    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (point, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let pixels = point * scale
        let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(size: pixels).write(to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(point)x\(point)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
    .write(to: root.appendingPathComponent("App/Assets.xcassets/Contents.json"))
print("Wrote \(images.count) icon images to \(iconSet.path)")
