import AppKit
import CoreGraphics

// Generate high-resolution macOS Big Sur style Stickman icon for Awake
func renderAwakeStickmanIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let s = size / 1024.0

    // 1. Squircle container (Standard macOS Big Sur spec: ~824x824 with padding)
    let iconRect = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let cornerRadius: CGFloat = 185 * s
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18 * s), blur: 35 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for inner drawing
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Off-white / light paper background gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.99, green: 0.99, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512 * s, y: 924 * s), end: CGPoint(x: 512 * s, y: 100 * s), options: [])
    }

    // Subtle inner border
    ctx.setLineWidth(max(1.0, 2.0 * s))
    ctx.setStrokeColor(NSColor(red: 0.82, green: 0.82, blue: 0.85, alpha: 1.0).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    // Line ink color
    let inkColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0).cgColor
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // 2. Hair Tufts on Top of Head (Messy sleepless doodle hair)
    ctx.saveGState()
    ctx.setStrokeColor(inkColor)
    ctx.setLineWidth(18 * s)
    
    // Hair 1 (curving left)
    let h1 = CGMutablePath()
    h1.move(to: CGPoint(x: 480 * s, y: 740 * s))
    h1.addQuadCurve(to: CGPoint(x: 440 * s, y: 830 * s), control: CGPoint(x: 450 * s, y: 785 * s))
    ctx.addPath(h1)
    ctx.strokePath()

    // Hair 2 (upright)
    let h2 = CGMutablePath()
    h2.move(to: CGPoint(x: 515 * s, y: 750 * s))
    h2.addQuadCurve(to: CGPoint(x: 520 * s, y: 845 * s), control: CGPoint(x: 512 * s, y: 800 * s))
    ctx.addPath(h2)
    ctx.strokePath()

    // Hair 3 (curving right)
    let h3 = CGMutablePath()
    h3.move(to: CGPoint(x: 550 * s, y: 740 * s))
    h3.addQuadCurve(to: CGPoint(x: 585 * s, y: 825 * s), control: CGPoint(x: 575 * s, y: 785 * s))
    ctx.addPath(h3)
    ctx.strokePath()
    ctx.restoreGState()

    // 3. Head (Large round circle)
    let headCenter = CGPoint(x: 512 * s, y: 510 * s)
    let headRadius: CGFloat = 240 * s
    let headRect = CGRect(x: headCenter.x - headRadius, y: headCenter.y - headRadius, width: headRadius * 2, height: headRadius * 2)

    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: headRect)
    ctx.setStrokeColor(inkColor)
    ctx.setLineWidth(26 * s)
    ctx.strokeEllipse(in: headRect)
    ctx.restoreGState()

    // 4. Sweat Drop (Temple, nervous/tired)
    ctx.saveGState()
    let sweatPath = CGMutablePath()
    sweatPath.move(to: CGPoint(x: 295 * s, y: 640 * s))
    sweatPath.addCurve(to: CGPoint(x: 275 * s, y: 600 * s), control1: CGPoint(x: 285 * s, y: 625 * s), control2: CGPoint(x: 275 * s, y: 615 * s))
    sweatPath.addArc(center: CGPoint(x: 295 * s, y: 600 * s), radius: 20 * s, startAngle: .pi, endAngle: 0, clockwise: true)
    sweatPath.addCurve(to: CGPoint(x: 295 * s, y: 640 * s), control1: CGPoint(x: 315 * s, y: 615 * s), control2: CGPoint(x: 305 * s, y: 625 * s))
    sweatPath.closeSubpath()
    ctx.setFillColor(NSColor(red: 0.88, green: 0.92, blue: 0.96, alpha: 0.8).cgColor)
    ctx.addPath(sweatPath)
    ctx.fillPath()
    ctx.setStrokeColor(inkColor)
    ctx.setLineWidth(7 * s)
    ctx.addPath(sweatPath)
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Eyebrows (Slightly furrowed / desperate to stay awake)
    ctx.saveGState()
    ctx.setStrokeColor(inkColor)
    ctx.setLineWidth(16 * s)
    
    // Left brow: slant slightly up towards center
    ctx.move(to: CGPoint(x: 345 * s, y: 645 * s))
    ctx.addLine(to: CGPoint(x: 445 * s, y: 660 * s))
    ctx.strokePath()

    // Right brow: slant slightly up towards center
    ctx.move(to: CGPoint(x: 679 * s, y: 645 * s))
    ctx.addLine(to: CGPoint(x: 579 * s, y: 660 * s))
    ctx.strokePath()
    ctx.restoreGState()

    // 6. Huge Wide Staring Eyes
    let eyeY: CGFloat = 555 * s
    let eyeRadius: CGFloat = 68 * s
    let leftEyeCenter = CGPoint(x: 405 * s, y: eyeY)
    let rightEyeCenter = CGPoint(x: 619 * s, y: eyeY)

    // Left Eye Circle
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: leftEyeCenter.x - eyeRadius, y: leftEyeCenter.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
    ctx.setStrokeColor(inkColor)
    ctx.setLineWidth(16 * s)
    ctx.strokeEllipse(in: CGRect(x: leftEyeCenter.x - eyeRadius, y: leftEyeCenter.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))

    // Right Eye Circle
    ctx.fillEllipse(in: CGRect(x: rightEyeCenter.x - eyeRadius, y: rightEyeCenter.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
    ctx.strokeEllipse(in: CGRect(x: rightEyeCenter.x - eyeRadius, y: rightEyeCenter.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
    ctx.restoreGState()

    // 7. Dark Under-Eye Bags (ขอบตาคล้ำเหมือนคนอดนอนทำงานหนัก)
    ctx.saveGState()
    // Soft shadow fill under left eye
    let leftBagPath = CGMutablePath()
    leftBagPath.move(to: CGPoint(x: 340 * s, y: 520 * s))
    leftBagPath.addQuadCurve(to: CGPoint(x: 470 * s, y: 520 * s), control: CGPoint(x: 405 * s, y: 445 * s))
    ctx.setFillColor(NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 0.18).cgColor)
    ctx.addPath(leftBagPath)
    ctx.fillPath()

    // Wrinkle arc 1 (left)
    ctx.setStrokeColor(NSColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 0.85).cgColor)
    ctx.setLineWidth(7 * s)
    let leftWrinkle1 = CGMutablePath()
    leftWrinkle1.move(to: CGPoint(x: 345 * s, y: 512 * s))
    leftWrinkle1.addQuadCurve(to: CGPoint(x: 465 * s, y: 512 * s), control: CGPoint(x: 405 * s, y: 460 * s))
    ctx.addPath(leftWrinkle1)
    ctx.strokePath()

    // Wrinkle arc 2 (left, smaller)
    ctx.setLineWidth(5 * s)
    let leftWrinkle2 = CGMutablePath()
    leftWrinkle2.move(to: CGPoint(x: 365 * s, y: 485 * s))
    leftWrinkle2.addQuadCurve(to: CGPoint(x: 445 * s, y: 485 * s), control: CGPoint(x: 405 * s, y: 450 * s))
    ctx.addPath(leftWrinkle2)
    ctx.strokePath()

    // Soft shadow fill under right eye
    let rightBagPath = CGMutablePath()
    rightBagPath.move(to: CGPoint(x: 554 * s, y: 520 * s))
    rightBagPath.addQuadCurve(to: CGPoint(x: 684 * s, y: 520 * s), control: CGPoint(x: 619 * s, y: 445 * s))
    ctx.setFillColor(NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 0.18).cgColor)
    ctx.addPath(rightBagPath)
    ctx.fillPath()

    // Wrinkle arc 1 (right)
    ctx.setLineWidth(7 * s)
    let rightWrinkle1 = CGMutablePath()
    rightWrinkle1.move(to: CGPoint(x: 559 * s, y: 512 * s))
    rightWrinkle1.addQuadCurve(to: CGPoint(x: 679 * s, y: 512 * s), control: CGPoint(x: 619 * s, y: 460 * s))
    ctx.addPath(rightWrinkle1)
    ctx.strokePath()

    // Wrinkle arc 2 (right, smaller)
    ctx.setLineWidth(5 * s)
    let rightWrinkle2 = CGMutablePath()
    rightWrinkle2.move(to: CGPoint(x: 579 * s, y: 485 * s))
    rightWrinkle2.addQuadCurve(to: CGPoint(x: 659 * s, y: 485 * s), control: CGPoint(x: 619 * s, y: 450 * s))
    ctx.addPath(rightWrinkle2)
    ctx.strokePath()
    ctx.restoreGState()

    // 8. Pinpoint Pupils (Wide awake staring look!)
    let pupilRadius: CGFloat = 17 * s
    ctx.saveGState()
    ctx.setFillColor(inkColor)
    // Left pupil
    ctx.fillEllipse(in: CGRect(x: leftEyeCenter.x - pupilRadius, y: leftEyeCenter.y - pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2))
    // Right pupil
    ctx.fillEllipse(in: CGRect(x: rightEyeCenter.x - pupilRadius, y: rightEyeCenter.y - pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2))

    // Tiny white highlight in pupils
    let glintRadius: CGFloat = 4.5 * s
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: leftEyeCenter.x + 3 * s, y: leftEyeCenter.y + 3 * s, width: glintRadius * 2, height: glintRadius * 2))
    ctx.fillEllipse(in: CGRect(x: rightEyeCenter.x + 3 * s, y: rightEyeCenter.y + 3 * s, width: glintRadius * 2, height: glintRadius * 2))
    ctx.restoreGState()

    // 9. Mouth (Straight, slightly tense line with corner ticks)
    ctx.saveGState()
    ctx.setStrokeColor(inkColor)
    ctx.setLineWidth(14 * s)
    
    // Main mouth line
    ctx.move(to: CGPoint(x: 455 * s, y: 380 * s))
    ctx.addLine(to: CGPoint(x: 569 * s, y: 380 * s))
    ctx.strokePath()

    // Small corner tick marks (funny nervous expression)
    ctx.setLineWidth(9 * s)
    ctx.move(to: CGPoint(x: 455 * s, y: 368 * s))
    ctx.addLine(to: CGPoint(x: 455 * s, y: 392 * s))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: 569 * s, y: 368 * s))
    ctx.addLine(to: CGPoint(x: 569 * s, y: 392 * s))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState() // pop squircle clip
    image.unlockFocus()
    return image
}

func getPNGData(image: NSImage, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
               from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// Generate sizes and package into ICNS directly
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "config"
let masterImage = renderAwakeStickmanIcon(size: 1024)

// Save 1024 PNG for preview/web
if let png1024 = getPNGData(image: masterImage, pixelSize: 1024) {
    try? png1024.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon_1024.png"))
}

// ICNS chunks: OSType -> pixel size
let chunks: [(String, Int)] = [
    ("ic10", 1024), // 1024x1024 or 512@2x
    ("ic09", 512),  // 512x512
    ("ic08", 256),  // 256x256
    ("ic07", 128),  // 128x128
    ("ic12", 64),   // 32@2x (64x64)
    ("ic11", 32)    // 16@2x (32x32)
]

var icnsData = Data()
icnsData.append("icns".data(using: .ascii)!)

var chunkBlocks = [Data]()
for (tag, pixelSize) in chunks {
    if let png = getPNGData(image: masterImage, pixelSize: pixelSize) {
        var chunk = Data()
        chunk.append(tag.data(using: .ascii)!)
        var chunkLen = UInt32(8 + png.count).bigEndian
        chunk.append(Data(bytes: &chunkLen, count: 4))
        chunk.append(png)
        chunkBlocks.append(chunk)
    }
}

var totalLength = UInt32(8 + chunkBlocks.reduce(0) { $0 + $1.count }).bigEndian
icnsData.append(Data(bytes: &totalLength, count: 4))
for block in chunkBlocks {
    icnsData.append(block)
}

let icnsPath = "\(outDir)/AppIcon.icns"
try? icnsData.write(to: URL(fileURLWithPath: icnsPath))
print("Successfully generated stickman icon: \(icnsPath)")
