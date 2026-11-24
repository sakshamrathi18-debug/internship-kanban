#!/usr/bin/env swift
// Turns a picture of the icon into the AppIcon set: finds the light rounded
// tile, trims the background around it, squares it to the macOS icon grid
// (824 px body in a 1024 canvas) and clips the corners to transparent.
// Run from the repo root:  swift scripts/icon_from_image.swift Design/icon-source.webp
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let iconSet = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")

guard let image = NSImage(contentsOf: source),
      let cgSource = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Can't read \(source.path)")
}

// Read pixels into RGBA.
let w = cgSource.width, h = cgSource.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
pixels.withUnsafeMutableBytes { buffer in
    let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cgSource, in: CGRect(x: 0, y: 0, width: w, height: h))
}

// The tile's rim is near-white; the backdrop is a warmer, darker cream.
func isRim(_ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
    return min(r, g, b) >= 248
}
// A column/row belongs to the tile when enough of it is rim-white.
let threshold = 0.25
func columnHit(_ x: Int) -> Bool { Double((0..<h).filter { isRim(x, $0) }.count) / Double(h) > threshold }
func rowHit(_ y: Int) -> Bool { Double((0..<w).filter { isRim($0, y) }.count) / Double(w) > threshold }
let minX = (0..<w).first(where: columnHit)!, maxX = (0..<w).last(where: columnHit)!
let minY = (0..<h).first(where: rowHit)!, maxY = (0..<h).last(where: rowHit)!
print("tile bounds x \(minX)…\(maxX), y \(minY)…\(maxY) (in rows from the top of the image)")
// Corner radius of the tile itself: walk the diagonal in from the top-left
// bounding corner to the rim; on a circular corner that distance is r(1 − 1/√2).
let step = (0..<min(maxX - minX, maxY - minY)).first { isRim(minX + $0, minY + $0) }!
let sourceRadius = CGFloat(step) / (1 - 1 / 2.squareRoot())
print("tile corner radius ≈ \(Int(sourceRadius)) px")
let tile = cgSource.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

func render(size: Int) -> Data {
    let s = CGFloat(size), unit = s / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = context.cgContext
    cg.interpolationQuality = .high
    let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    // Keep the tile's own corners (scaled with it) so its rim stays even.
    let cw = sourceRadius * body.width / CGFloat(tile.width), ch = sourceRadius * body.height / CGFloat(tile.height)
    let path = CGPath(roundedRect: body, cornerWidth: cw, cornerHeight: ch, transform: nil)
    // Soft drop shadow like system icons.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 28 * unit,
                 color: CGColor(gray: 0, alpha: 0.22))
    cg.addPath(path); cg.setFillColor(CGColor(gray: 1, alpha: 1)); cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(path); cg.clip()
    cg.draw(tile, in: body)
    cg.restoreGState()
    return rep.representation(using: .png, properties: [:])!
}

for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(point)x\(point).png" : "icon_\(point)x\(point)@2x.png"
        try render(size: point * scale).write(to: iconSet.appendingPathComponent(name))
    }
}
try render(size: 1024).write(to: root.appendingPathComponent("Design/AppIcon-1024.png"))
print("wrote AppIcon set and Design/AppIcon-1024.png")
