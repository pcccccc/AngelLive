#!/usr/bin/env swift
import AppKit
import CoreText

// Run with Xcode's Swift toolchain. This renders assets without launching an app.
struct Layout: Decodable {
    let width, height, iconSize, labelSize: CGFloat
    let applicationPosition, applicationsPosition: [CGFloat]
    let collaboration, title, instruction, footer: String
}

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repository = directory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: directory.appendingPathComponent("layout.json")))

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

@MainActor
struct Canvas {
    let height: CGFloat

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x, y: self.height - y - height, width: width, height: height)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: height - y) }

    func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
              weight: NSFont.Weight = .regular, ink: UInt32 = 0x292426, tracking: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color(ink), .paragraphStyle: paragraph, .kern: tracking
        ]
        (value as NSString).draw(in: rect(x, y, width, size * 1.65), withAttributes: attributes)
    }

    func centeredText(_ value: String, in bounds: NSRect, size: CGFloat,
                      weight: NSFont.Weight = .regular, ink: UInt32 = 0x292426) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): NSFont.systemFont(ofSize: size, weight: weight),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(ink).cgColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        // Center the visible glyphs, including mixed Latin/Chinese text, rather
        // than centering a line box with asymmetric ascender/descender padding.
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = NSGraphicsContext.current!.cgContext
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: bounds.midX - glyphBounds.midX,
                                       y: bounds.midY - glyphBounds.midY)
        CTLineDraw(line, context)
    }

    func halo(x: CGFloat, y: CGFloat, radius: CGFloat, tint: UInt32, opacity: CGFloat) {
        let context = NSGraphicsContext.current!.cgContext
        let colors = [color(tint, alpha: opacity).cgColor, color(tint, alpha: 0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        let center = point(x, y)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius, options: [])
    }
}

@MainActor
func drawBackground() {
    let canvas = Canvas(height: layout.height)
    color(0xFCFAF8).setFill()
    canvas.rect(0, 0, layout.width, layout.height).fill()
    canvas.halo(x: 710, y: -70, radius: 475, tint: 0xF6297B, opacity: 0.12)
    canvas.halo(x: -80, y: 480, radius: 430, tint: 0xFFA955, opacity: 0.21)

    let badgeBounds = canvas.rect(248, 36, 224, 30)
    let badge = NSBezierPath(roundedRect: badgeBounds, xRadius: 15, yRadius: 15)
    color(0xFFFFFF, alpha: 0.75).setFill()
    badge.fill()
    color(0xE7D8D8).setStroke()
    badge.lineWidth = 0.7
    badge.stroke()
    canvas.centeredText(layout.collaboration, in: badgeBounds, size: 12.5, weight: .medium, ink: 0x63515A)
    canvas.text(layout.title, x: 48, y: 89, width: 624, size: 32, weight: .semibold, tracking: -0.7)
    canvas.text(layout.instruction, x: 48, y: 143, width: 624, size: 14, ink: 0x74686C)

    let arrowY = layout.applicationPosition[1]
    let arrow = NSBezierPath()
    arrow.move(to: canvas.point(333, arrowY))
    arrow.line(to: canvas.point(387, arrowY))
    arrow.move(to: canvas.point(378, arrowY - 9))
    arrow.line(to: canvas.point(387, arrowY))
    arrow.line(to: canvas.point(378, arrowY + 9))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0xB97882).setStroke()
    arrow.stroke()

    color(0xE5DDDA).setFill()
    canvas.rect(282, 394, 156, 0.6).fill()
    canvas.text(layout.footer, x: 48, y: 414, width: 624, size: 11.5, ink: 0x77696D)
}

@MainActor
func drawPreviewIcons() throws {
    let canvas = Canvas(height: layout.height)
    let artwork = repository.appendingPathComponent("macOS/AngelLiveMacOS/XiaoShengBB.icon/Assets/AngelLive_XiaoShengBB.png")
    guard let app = NSImage(contentsOf: artwork),
          let applications = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns") else {
        throw NSError(domain: "DMGDesign", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing app artwork or macOS Applications icon."])
    }
    let size = layout.iconSize
    let appBounds = canvas.rect(layout.applicationPosition[0] - size / 2, layout.applicationPosition[1] - size / 2, size, size)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: -5)
    shadow.shadowColor = color(0x6D2A39, alpha: 0.12)
    shadow.set()
    color(0xF43F72).setFill()
    NSBezierPath(roundedRect: appBounds, xRadius: size * 0.224, yRadius: size * 0.224).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: appBounds, xRadius: size * 0.224, yRadius: size * 0.224).addClip()
    app.draw(in: appBounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    applications.draw(in: canvas.rect(layout.applicationsPosition[0] - size / 2, layout.applicationsPosition[1] - size / 2, size, size),
                      from: .zero, operation: .sourceOver, fraction: 1)
    canvas.text("Angel Live", x: layout.applicationPosition[0] - 100, y: layout.applicationPosition[1] + size / 2 + 11,
                width: 200, size: layout.labelSize, weight: .medium)
    canvas.text("Applications", x: layout.applicationsPosition[0] - 100, y: layout.applicationsPosition[1] + size / 2 + 11,
                width: 200, size: layout.labelSize, weight: .medium)
}

@MainActor
func render(name: String, width: CGFloat, height: CGFloat, scale: CGFloat, draw: () throws -> Void) throws {
    let pixelsWide = Int(width * scale), pixelsHigh = Int(height * scale)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    // bitmap.size already establishes the point-to-pixel scale for AppKit.
    try draw()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DMGDesign", code: 2)
    }
    try data.write(to: directory.appendingPathComponent(name))
    print("Rendered \(name): \(pixelsWide) × \(pixelsHigh)")
}

try render(name: "background.png", width: layout.width, height: layout.height, scale: 1) { drawBackground() }
try render(name: "background@2x.png", width: layout.width, height: layout.height, scale: 2) { drawBackground() }
try render(name: "preview.png", width: 832, height: 600, scale: 2) {
    let canvas = Canvas(height: 600)
    color(0xEDE9E6).setFill()
    canvas.rect(0, 0, 832, 600).fill()
    canvas.halo(x: 750, y: 55, radius: 580, tint: 0xF7D5E0, opacity: 0.55)
    let window = NSBezierPath(roundedRect: canvas.rect(56, 48, 720, 492), xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowColor = color(0x37252D, alpha: 0.20)
    shadow.set()
    color(0xFAF8F7).setFill()
    window.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    window.addClip()
    color(0xF5F2F0).setFill()
    canvas.rect(56, 48, 720, 32).fill()
    for (index, tint) in [UInt32(0xFF6159), 0xFFBD2E, 0x28C840].enumerated() {
        color(tint).setFill()
        NSBezierPath(ovalIn: canvas.rect(70 + CGFloat(index) * 20, 59, 11, 11)).fill()
    }
    canvas.text("AngelLive", x: 280, y: 56, width: 272, size: 13, weight: .medium, ink: 0x655E60)
    NSGraphicsContext.current!.cgContext.translateBy(x: 56, y: 60)
    drawBackground()
    try drawPreviewIcons()
    NSGraphicsContext.restoreGraphicsState()
}
