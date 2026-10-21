import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        let mint = NSColor(calibratedRed: 0.53, green: 0.91, blue: 0.78, alpha: 1)
        let rect = NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.9, height: p * 0.9)
        let rounded = NSBezierPath(roundedRect: rect, xRadius: p * 0.20, yRadius: p * 0.20)
        NSGradient(starting: NSColor(calibratedRed: 0.105, green: 0.18, blue: 0.20, alpha: 1),
                   ending: NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.085, alpha: 1))!.draw(in: rounded, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        rounded.addClip()
        for radius in [0.29, 0.38, 0.47] {
            let r = p * radius
            let ring = NSBezierPath(ovalIn: NSRect(x: p * 0.5 - r, y: p * 0.53 - r, width: 2 * r, height: 2 * r))
            mint.withAlphaComponent(0.075).setStroke()
            ring.lineWidth = max(0.5, p * 0.001)
            ring.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        rounded.lineWidth = max(0.5, p * 0.001)
        rounded.stroke()
        var transform = AffineTransform(translationByX: p * 0.18, byY: p * 0.84)
        transform.scale(x: p * 0.0064, y: -p * 0.0064)
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 50, y: 82))
        mark.curve(to: NSPoint(x: 21, y: 40), controlPoint1: NSPoint(x: 41, y: 70), controlPoint2: NSPoint(x: 21, y: 58))
        mark.curve(to: NSPoint(x: 50, y: 12), controlPoint1: NSPoint(x: 21, y: 24), controlPoint2: NSPoint(x: 34, y: 12))
        mark.curve(to: NSPoint(x: 79, y: 40), controlPoint1: NSPoint(x: 66, y: 12), controlPoint2: NSPoint(x: 79, y: 24))
        mark.curve(to: NSPoint(x: 50, y: 82), controlPoint1: NSPoint(x: 79, y: 58), controlPoint2: NSPoint(x: 59, y: 70))
        mark.line(to: NSPoint(x: 50, y: 87))
        mark.curve(to: NSPoint(x: 62, y: 96), controlPoint1: NSPoint(x: 50, y: 93), controlPoint2: NSPoint(x: 54, y: 96))
        mark.line(to: NSPoint(x: 79, y: 96))
        mark.appendOval(in: NSRect(x: 39, y: 29, width: 22, height: 22))
        mark.transform(using: transform)
        mark.lineWidth = p * 0.038
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        mint.setStroke()
        mark.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: destination.appendingPathComponent(name))
    }
}
