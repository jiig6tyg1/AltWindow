import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 190, yRadius: 190)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.systemBlue.setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.14, green: 0.19, blue: 0.64, alpha: 1),
                        NSColor(red: 0.18, green: 0.48, blue: 0.91, alpha: 1),
                        NSColor(red: 0.22, green: 0.82, blue: 0.91, alpha: 1)])!.draw(in: base, angle: 45)
    NSColor.white.withAlphaComponent(0.35).setStroke()
    base.lineWidth = 3
    base.stroke()

    let back = NSBezierPath(roundedRect: NSRect(x: 220, y: 362, width: 464, height: 386), xRadius: 54, yRadius: 54)
    NSColor.white.withAlphaComponent(0.23).setFill()
    back.fill()
    NSColor.white.withAlphaComponent(0.8).setStroke()
    back.lineWidth = 9
    back.stroke()
    let backLine = NSBezierPath()
    backLine.move(to: NSPoint(x: 225, y: 665)); backLine.line(to: NSPoint(x: 680, y: 665))
    backLine.lineWidth = 7; backLine.stroke()

    let front = NSBezierPath(roundedRect: NSRect(x: 342, y: 258, width: 464, height: 384), xRadius: 54, yRadius: 54)
    NSGraphicsContext.saveGraphicsState()
    shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.set()
    NSColor(red: 0.83, green: 0.97, blue: 1, alpha: 0.96).setFill(); front.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.95).setStroke(); front.lineWidth = 8; front.stroke()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 347, y: 562)); line.line(to: NSPoint(x: 801, y: 562))
    NSColor(red: 0.25, green: 0.55, blue: 0.77, alpha: 0.3).setStroke()
    line.lineWidth = 5; line.stroke()
    for x in [385, 411, 437] {
        NSColor(red: 0.18, green: 0.47, blue: 0.75, alpha: 0.6).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: 591, width: 12, height: 12)).fill()
    }
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 451, y: 417)); arrow.line(to: NSPoint(x: 693, y: 417))
    arrow.move(to: NSPoint(x: 619, y: 489)); arrow.line(to: NSPoint(x: 693, y: 417)); arrow.line(to: NSPoint(x: 619, y: 345))
    arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.lineWidth = 27
    NSColor(red: 0.12, green: 0.39, blue: 0.72, alpha: 1).setStroke(); arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for pointSize in [16, 32, 128, 256, 512] {
    try render(pointSize).write(to: destination.appendingPathComponent("icon_\(pointSize)x\(pointSize).png"))
    try render(pointSize * 2).write(to: destination.appendingPathComponent("icon_\(pointSize)x\(pointSize)@2x.png"))
}
