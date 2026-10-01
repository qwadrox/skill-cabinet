import AppKit

// Render at both scales so Finder displays the background sharply on Retina Macs.
let size = NSSize(width: 660, height: 400)
let image = NSImage(size: size)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 660 * scale, pixelsHigh: 400 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSGradient(colors: [
        NSColor(calibratedRed: 0.95, green: 0.96, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.99, alpha: 1)
    ])!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    let title = "Skill Cabinet" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.38, alpha: 1)
    ]
    let titleSize = title.size(withAttributes: attributes)
    title.draw(at: NSPoint(x: (size.width - titleSize.width) / 2, y: 310), withAttributes: attributes)

    // Finder icon centers are (170, 205) and (490, 205), measured from the top.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 303, y: 195))
    arrow.line(to: NSPoint(x: 357, y: 195))
    arrow.move(to: NSPoint(x: 345, y: 207))
    arrow.line(to: NSPoint(x: 357, y: 195))
    arrow.line(to: NSPoint(x: 345, y: 183))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedRed: 0.39, green: 0.47, blue: 0.74, alpha: 1).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
