// Renders Lad's app icon into an .iconset directory (make icon turns it into AppIcon.icns).
//
// A keycap with two legends, L and Л, on a blue-over-yellow squircle.
// Usage: swift tools/make_icon.swift Resources/AppIcon.iconset

import AppKit

let canvas: CGFloat = 1024
let blue = NSColor(srgbRed: 0.0, green: 0.341, blue: 0.718, alpha: 1)
let yellow = NSColor(srgbRed: 1.0, green: 0.835, blue: 0.0, alpha: 1)
let ink = NSColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1)

func drawIcon() {
    // macOS icon grid: an 824-point squircle centred on the 1024 canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    yellow.setFill()
    tile.fill()
    blue.setFill()
    NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2).fill()
    NSGraphicsContext.restoreGraphicsState()

    let cap = NSRect(x: 252, y: 236, width: 520, height: 540)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 36
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(white: 0.86, alpha: 1).setFill()
    NSBezierPath(roundedRect: cap, xRadius: 96, yRadius: 96).fill()
    NSGraphicsContext.restoreGraphicsState()
    let top = NSRect(x: cap.minX + 28, y: cap.minY + 56, width: cap.width - 56, height: cap.height - 84)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: top, xRadius: 76, yRadius: 76).fill()

    legend("L", color: blue, at: NSPoint(x: top.minX + 58, y: top.maxY - 250))
    legend("Л", color: ink, at: NSPoint(x: top.maxX - 230, y: top.minY + 32))
}

func legend(_ text: String, color: NSColor, at origin: NSPoint) {
    let font = NSFont.systemFont(ofSize: 210, weight: .heavy)
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]).draw(at: origin)
}

func render(pixels: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(pixels) / canvas
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make_icon.swift <out.iconset>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        guard let png = render(pixels: points * scale) else {
            FileHandle.standardError.write(Data("could not render \(name)\n".utf8))
            exit(1)
        }
        try png.write(to: output.appending(path: name))
    }
}
