import AppKit
import CoreText
import Foundation

private let canvasWidth: CGFloat = 720
private let canvasHeight: CGFloat = 460

private func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        deviceRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: alpha
    )
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("DMG background failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4,
      let scale = Int(CommandLine.arguments[3]),
      scale == 1 || scale == 2 else {
    fail("usage: swift render_background.swift <DesignSystem> <output.png> <1|2>")
}

let designSystemURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let paperURL = designSystemURL.appendingPathComponent("assets/logo/source/paper-texture-2048.png")
let markURL = designSystemURL.appendingPathComponent("assets/logo/exports/transparent/weibei-mark-flat-1024.png")
let fontURL = designSystemURL.appendingPathComponent("assets/fonts/WeiBeiStele.ttf")

guard let paper = NSImage(contentsOf: paperURL),
      let mark = NSImage(contentsOf: markURL) else {
    fail("missing paper texture or WeiBei mark")
}

CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

let pixelWidth = Int(canvasWidth) * scale
let pixelHeight = Int(canvasHeight) * scale
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fail("could not create bitmap context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high
graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

let canvas = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
color(247, 240, 228).setFill()
canvas.fill()
paper.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 0.18)

color(35, 31, 28, alpha: 0.05).setFill()
NSRect(x: 0, y: 0, width: canvasWidth, height: 1).fill()
NSRect(x: 0, y: canvasHeight - 1, width: canvasWidth, height: 1).fill()

mark.draw(
    in: NSRect(x: 584, y: 328, width: 112, height: 112),
    from: .zero,
    operation: .sourceOver,
    fraction: 0.055
)

let brandFont = NSFont(name: "WeiBeiStele-Regular", size: 30) ?? NSFont.systemFont(ofSize: 30, weight: .semibold)
let instructionFont = NSFont.systemFont(ofSize: 20, weight: .medium)
let detailFont = NSFont.systemFont(ofSize: 12, weight: .regular)
let centered = NSMutableParagraphStyle()
centered.alignment = .center

("WEIBEI" as NSString).draw(
    at: NSPoint(x: 38, y: 386),
    withAttributes: [
        .font: brandFont,
        .foregroundColor: color(35, 31, 28),
        .kern: 2.8,
    ]
)

("拖入“应用程序”即可安装" as NSString).draw(
    in: NSRect(x: 120, y: 349, width: 480, height: 30),
    withAttributes: [
        .font: instructionFont,
        .foregroundColor: color(35, 31, 28),
        .paragraphStyle: centered,
    ]
)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 287, y: 191))
arrow.line(to: NSPoint(x: 430, y: 191))
arrow.move(to: NSPoint(x: 416, y: 202))
arrow.line(to: NSPoint(x: 430, y: 191))
arrow.line(to: NSPoint(x: 416, y: 180))
arrow.lineWidth = 2
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(77, 102, 122, alpha: 0.82).setStroke()
arrow.stroke()

color(170, 42, 35).setFill()
NSRect(x: 38, y: 46, width: 9, height: 9).fill()

("macOS 14+  ·  Apple 芯片  ·  读、记、问，回到出处" as NSString).draw(
    at: NSPoint(x: 58, y: 42),
    withAttributes: [
        .font: detailFont,
        .foregroundColor: color(104, 97, 87),
        .kern: 0.3,
    ]
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
    fail("could not encode PNG")
}
do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    fail(error.localizedDescription)
}
