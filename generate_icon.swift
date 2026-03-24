#!/usr/bin/env swift
// Run from repo root:  swift generate_icon.swift
import AppKit
import CoreText

let size = 1024
let s    = CGFloat(size)

// Use CGContext directly to guarantee exactly 1024×1024 (not screen-scale dependent)
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { print("No context"); exit(1) }

// CGContext origin is bottom-left; flip to top-left (matches PNG/screen orientation)
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

let space = CGColorSpaceCreateDeviceRGB()

// Now coordinates: origin top-left, Y increases downward (matches screen/PNG)
// Background gradient: top-left purple → bottom-right teal
let bgGrad = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(red: 0.08, green: 0.02, blue: 0.28, alpha: 1),
        CGColor(red: 0.0,  green: 0.20, blue: 0.42, alpha: 1),
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bgGrad,
    start: CGPoint(x: 0, y: 0),
    end:   CGPoint(x: s, y: s),
    options: [])

// Card & $ share centre: image centre shifted DOWN 30pt (SwiftUI .offset(y:30))
let cx = s / 2
let cy = s / 2 + 30

// SwiftUI .rotationEffect(.degrees(-8)) = -8° in Y-down = clockwise
// CGContext Y-down: positive angle = clockwise → use +8°
let angle = CGFloat(8.0 * Double.pi / 180.0)

// ── Card ──────────────────────────────────────────────────────────────
let cW: CGFloat = 700, cH: CGFloat = 460

ctx.saveGState()
ctx.translateBy(x: cx, y: cy)
ctx.rotate(by: angle)
ctx.translateBy(x: -cW / 2, y: -cH / 2)

let cardPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: cW, height: cH),
                      cornerWidth: 60, cornerHeight: 60, transform: nil)

// Card body gradient: top-left → bottom-right (Y-down)
ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
let cardGrad = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(red: 0.55, green: 0.42, blue: 1.0,  alpha: 1),
        CGColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1),
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(cardGrad,
    start: CGPoint(x: 0,    y: 0),
    end:   CGPoint(x: cW,   y: cH),
    options: [])

// Sheen: top → centre, white.opacity(0.22) → clear
let sheenGrad = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(sheenGrad,
    start: CGPoint(x: cW / 2, y: 0),
    end:   CGPoint(x: cW / 2, y: cH / 2),
    options: [])
ctx.restoreGState()

ctx.restoreGState()

// ── $ symbol (CoreText, works in pure CGContext) ───────────────────────
ctx.saveGState()
ctx.translateBy(x: cx, y: cy)
ctx.rotate(by: angle)

let ctFont = CTFontCreateWithName("SF Pro Display" as CFString, 310, nil)
let dollar = NSAttributedString(string: "$", attributes: [
    kCTFontAttributeName as NSAttributedString.Key: ctFont,
    kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
])
let line = CTLineCreateWithAttributedString(dollar)
let bounds = CTLineGetBoundsWithOptions(line, [])
ctx.textPosition = CGPoint(x: -bounds.width / 2 - bounds.minX,
                            y: -bounds.height / 2 - bounds.minY)
CTLineDraw(line, ctx)

ctx.restoreGState()

// ── Export ────────────────────────────────────────────────────────────
guard let cgImage = ctx.makeImage() else { print("❌  makeImage failed"); exit(1) }
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    print("❌  PNG encode failed"); exit(1)
}

let dest = URL(fileURLWithPath: "expenses/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
do {
    try png.write(to: dest)
    print("✅  AppIcon.png written — clean-build the app in Xcode (Product → Clean Build Folder, then ⌘B)")
} catch {
    print("❌  \(error)"); exit(1)
}
