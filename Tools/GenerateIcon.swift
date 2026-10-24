import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    let frame = NSRect(x: 80, y: 80, width: 864, height: 864)
    let shape = NSBezierPath(roundedRect: frame, xRadius: 198, yRadius: 198)
    NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.26, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: NSColor(calibratedRed: 0.52, green: 0.74, blue: 0.65, alpha: 1),
               ending: NSColor(calibratedRed: 0.19, green: 0.43, blue: 0.35, alpha: 1))!.draw(in: shape, angle: 90)
    NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.66, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 620, y: 620, width: 142, height: 142)).fill()

    for (offset, color) in [
        (CGFloat(0), NSColor(calibratedRed: 0.30, green: 0.56, blue: 0.45, alpha: 1)),
        (CGFloat(-150), NSColor(calibratedRed: 0.17, green: 0.40, blue: 0.33, alpha: 1)),
        (CGFloat(-300), NSColor(calibratedRed: 0.10, green: 0.26, blue: 0.23, alpha: 1))
    ] {
        let hill = NSBezierPath()
        hill.move(to: NSPoint(x: 60, y: 480 + offset))
        hill.curve(to: NSPoint(x: 970, y: 530 + offset), controlPoint1: NSPoint(x: 400, y: 830 + offset), controlPoint2: NSPoint(x: 660, y: 140 + offset))
        hill.line(to: NSPoint(x: 970, y: 60))
        hill.line(to: NSPoint(x: 60, y: 60))
        hill.close()
        color.setFill()
        hill.fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    let back = NSBezierPath(roundedRect: NSRect(x: 300, y: 377, width: 464, height: 310), xRadius: 36, yRadius: 36)
    NSColor.white.withAlphaComponent(0.35).setStroke()
    back.lineWidth = 17
    back.stroke()
    let front = NSBezierPath(roundedRect: NSRect(x: 235, y: 305, width: 464, height: 310), xRadius: 36, yRadius: 36)
    NSColor(calibratedRed: 0.13, green: 0.31, blue: 0.26, alpha: 0.32).setFill()
    front.fill()
    NSColor.white.withAlphaComponent(0.94).setStroke()
    front.lineWidth = 20
    front.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

for logicalSize in [16, 32, 128, 256, 512] {
    try render(size: logicalSize, to: output.appendingPathComponent("icon_\(logicalSize)x\(logicalSize).png"))
    try render(size: logicalSize * 2, to: output.appendingPathComponent("icon_\(logicalSize)x\(logicalSize)@2x.png"))
}

// ICNS supports PNG representations directly. Writing the container avoids a Launch Services dependency.
if CommandLine.arguments.count > 2 {
    func lengthData(_ value: Int) -> Data {
        var number = UInt32(value).bigEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
    let representations = [
        ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"),
        ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png")
    ]
    var payload = Data()
    for (tag, filename) in representations {
        let png = try Data(contentsOf: output.appendingPathComponent(filename))
        payload.append(Data(tag.utf8))
        payload.append(lengthData(png.count + 8))
        payload.append(png)
    }
    var icon = Data("icns".utf8)
    icon.append(lengthData(payload.count + 8))
    icon.append(payload)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
