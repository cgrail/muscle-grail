// Draws the app icon and image, a flexed arm. Run from the repo root: swift Design/FlexArm.swift
// Writes the iPhone and watch icons (full bleed, no alpha), the macOS icon sizes (an inset rounded square)
// into the asset catalogs, and Design/flex-arm.png, the arm alone.
import CoreGraphics
import Foundation
import ImageIO

let size = 1024.0
let red = CGColor(red: 0.78, green: 0.06, blue: 0.16, alpha: 1)
let orange = CGColor(red: 1, green: 0.42, blue: 0.2, alpha: 1)
let gradient = CGGradient(colorsSpace: nil, colors: [orange, red] as CFArray, locations: [0, 1])!

/// The arm's outline in a 1024 square, y down: upper arm along the bottom, forearm up, fist on top, biceps bulging.
func arm() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 150, y: 840))
    p.addCurve(to: CGPoint(x: 700, y: 850), control1: CGPoint(x: 330, y: 880), control2: CGPoint(x: 560, y: 880))
    p.addCurve(to: CGPoint(x: 860, y: 690), control1: CGPoint(x: 800, y: 830), control2: CGPoint(x: 870, y: 770))
    p.addCurve(to: CGPoint(x: 810, y: 390), control1: CGPoint(x: 855, y: 590), control2: CGPoint(x: 820, y: 480))
    p.addCurve(to: CGPoint(x: 820, y: 220), control1: CGPoint(x: 845, y: 340), control2: CGPoint(x: 850, y: 260))
    p.addCurve(to: CGPoint(x: 590, y: 190), control1: CGPoint(x: 770, y: 150), control2: CGPoint(x: 640, y: 140))
    p.addCurve(to: CGPoint(x: 600, y: 390), control1: CGPoint(x: 540, y: 240), control2: CGPoint(x: 545, y: 340))
    p.addCurve(to: CGPoint(x: 610, y: 560), control1: CGPoint(x: 625, y: 440), control2: CGPoint(x: 625, y: 500))
    p.addCurve(to: CGPoint(x: 200, y: 600), control1: CGPoint(x: 560, y: 370), control2: CGPoint(x: 300, y: 360))
    p.addCurve(to: CGPoint(x: 150, y: 840), control1: CGPoint(x: 150, y: 660), control2: CGPoint(x: 130, y: 760))
    p.closeSubpath()
    return p
}

/// Muscle and finger lines, drawn in the background color over the white arm.
func lines() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 290, y: 720)) // under the biceps
    p.addCurve(to: CGPoint(x: 600, y: 650), control1: CGPoint(x: 400, y: 760), control2: CGPoint(x: 540, y: 730))
    p.move(to: CGPoint(x: 700, y: 760)) // elbow crease
    p.addCurve(to: CGPoint(x: 760, y: 640), control1: CGPoint(x: 735, y: 730), control2: CGPoint(x: 755, y: 690))
    for y in [255.0, 305, 355] { // curled fingers, seen from the inside
        p.move(to: CGPoint(x: 588, y: y))
        p.addLine(to: CGPoint(x: 650, y: y + 4))
    }
    return p
}

func image(_ draw: (CGContext) -> Void, alpha: Bool, pixels: Int = 1024) -> CGImage {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue)!
    context.translateBy(x: 0, y: Double(pixels)) // draw y down in a 1024 square, like the paths
    context.scaleBy(x: Double(pixels) / size, y: -Double(pixels) / size)
    draw(context)
    return context.makeImage()!
}

/// The background gradient over `rect`, then the arm scaled into it.
func icon(_ context: CGContext, in rect: CGRect) {
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: rect.width / size, y: rect.height / size)
    drawArm(context, lineColor: red, scale: 0.8) // small enough for the watch's round mask
}

/// The arm centred in the 1024 square at `scale`.
func drawArm(_ context: CGContext, lineColor: CGColor, scale: Double, gradientFill: Bool = false) {
    let box = arm().boundingBoxOfPath
    context.translateBy(x: size / 2, y: size / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.midX, y: -box.midY)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(arm())
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()
    if gradientFill { // on its own, the arm takes the icon's colors so it shows on any background
        context.saveGState()
        context.addPath(arm())
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.maxX, y: box.maxY), options: [])
        context.restoreGState()
    }
    context.addPath(lines())
    context.setStrokeColor(lineColor)
    context.setLineWidth(22)
    context.setLineCap(.round)
    context.strokePath()
}

func write(_ image: CGImage, _ path: String) {
    let url = URL(filePath: path)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let square = image({ icon($0, in: CGRect(x: 0, y: 0, width: size, height: size)) }, alpha: false)
write(square, "App/Assets.xcassets/AppIcon.appiconset/icon.png")
write(square, "Watch/Assets.xcassets/AppIcon.appiconset/icon.png")
func mac(_ context: CGContext) {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824) // macOS icon grid: 824 px shape, room for its shadow
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.setFillColor(red)
    context.fillPath()
    context.restoreGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.clip()
    icon(context, in: rect)
}
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    write(image(mac, alpha: true, pixels: pixels), "App/Assets.xcassets/AppIcon.appiconset/mac-\(pixels).png")
}
write(image({ drawArm($0, lineColor: CGColor(gray: 1, alpha: 1), scale: 0.95, gradientFill: true) }, alpha: true), "Design/flex-arm.png")
