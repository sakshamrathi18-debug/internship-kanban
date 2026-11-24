#!/usr/bin/env swift
// Draws the dark app icon: the same three-lane board as Design/icon-source.webp
// (rim, lanes and cards in the same places) in the board's dark-mode colours,
// on the standard macOS icon grid (824 px body in a 1024 canvas).
// Run from the repo root:  swift scripts/make_icon_dark.swift
// The iPhone icon is full-bleed and square (iOS rounds the corners itself).
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let rim = color(0x2B2826), lane = color(0x1A1817)
let high = color(0xE39385), medium = color(0xE6C27A), low = color(0x96C7A6)
let none = color(0xE8E4DF), done = color(0x56524E)

// Layout in the source picture's pixels (its tile spans x 29…987, y 42…896, top-down).
let tileRect = CGRect(x: 29, y: 42, width: 958, height: 854)
let lanes = [CGRect(x: 62, y: 80, width: 288, height: 780),
             CGRect(x: 373, y: 80, width: 267, height: 780),
             CGRect(x: 663, y: 80, width: 292, height: 780)]
let cards: [(CGRect, CGColor)] = [
    (CGRect(x: 107, y: 153, width: 208, height: 294), high),
    (CGRect(x: 107, y: 493, width: 208, height: 290), low),
    (CGRect(x: 404, y: 153, width: 204, height: 179), high),
    (CGRect(x: 404, y: 378, width: 204, height: 180), medium),
    (CGRect(x: 404, y: 605, width: 204, height: 178), none),
    (CGRect(x: 698, y: 153, width: 211, height: 630), done),
]

func drawIcon(size: Int, iOS: Bool = false) -> Data {
    let s = CGFloat(size), unit = s / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let body = iOS ? CGRect(x: 0, y: 0, width: s, height: s)
                   : CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let cornerRadius = iOS ? 0.2237 * s : 186 * unit

    // Source pixels → canvas (flipping y, since Core Graphics counts from the bottom).
    func map(_ r: CGRect) -> CGRect {
        let sx = body.width / tileRect.width, sy = body.height / tileRect.height
        return CGRect(x: body.minX + (r.minX - tileRect.minX) * sx,
                      y: body.maxY - (r.maxY - tileRect.minY) * sy,
                      width: r.width * sx, height: r.height * sy)
    }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // Tile with a soft system-style shadow.
    if iOS {
        cg.setFillColor(rim); cg.fill(body)
    } else {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 28 * unit, color: CGColor(gray: 0, alpha: 0.3))
        cg.addPath(rounded(body, cornerRadius)); cg.setFillColor(rim); cg.fillPath()
        cg.restoreGState()
    }

    // Lanes, clipped to the tile's inner edge so the rim stays even.
    let inset = map(lanes[0]).minX - body.minX
    cg.saveGState()
    cg.addPath(rounded(body.insetBy(dx: inset, dy: inset), cornerRadius - inset)); cg.clip()
    cg.setFillColor(lane)
    for l in lanes { cg.fill(map(l)) }
    cg.restoreGState()

    for (rect, fill) in cards {
        cg.addPath(rounded(map(rect), 38 * unit)); cg.setFillColor(fill); cg.fillPath()
    }
    return rep.representation(using: .png, properties: [:])!
}

if CommandLine.arguments.contains("--ios") {
    let set = root.appendingPathComponent("iOS/Assets.xcassets/AppIcon.appiconset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try drawIcon(size: 1024, iOS: true).write(to: set.appendingPathComponent("icon-1024.png"))
    let contents = #"{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#
    try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    try #"{"info":{"author":"xcode","version":1}}"#.write(to: root.appendingPathComponent("iOS/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
    print("wrote iOS AppIcon")
    exit(0)
}

for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(point)x\(point).png" : "icon_\(point)x\(point)@2x.png"
        try drawIcon(size: point * scale).write(to: iconSet.appendingPathComponent(name))
    }
}
try drawIcon(size: 1024).write(to: root.appendingPathComponent("Design/AppIcon-dark-1024.png"))
print("wrote dark AppIcon set and Design/AppIcon-dark-1024.png")
