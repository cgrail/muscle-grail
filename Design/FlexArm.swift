// Draws the app icon and image, a flexed arm. Run from the repo root: swift Design/FlexArm.swift
// Writes the iPhone and watch icons (full bleed, no alpha), the macOS icon sizes (an inset rounded square)
// into the asset catalogs, and Design/flex-arm.png, the arm alone.
import CoreGraphics
import Foundation
import ImageIO

let size = 1024.0
let red = CGColor(red: 0.86, green: 0.13, blue: 0.2, alpha: 1)
let darkRed = CGColor(red: 0.42, green: 0.03, blue: 0.09, alpha: 1)
let background = CGGradient(colorsSpace: nil, colors: [red, darkRed] as CFArray, locations: [0, 1])!
let skinLight = CGColor(red: 1, green: 0.85, blue: 0.7, alpha: 1)
let skin = CGColor(red: 0.95, green: 0.71, blue: 0.53, alpha: 1)
let skinShadow = CGColor(red: 0.72, green: 0.43, blue: 0.28, alpha: 1)

func curve(_ p: CGMutablePath, _ to: (Double, Double), _ c1: (Double, Double), _ c2: (Double, Double)) {
    p.addCurve(to: CGPoint(x: to.0, y: to.1), control1: CGPoint(x: c1.0, y: c1.1), control2: CGPoint(x: c2.0, y: c2.1))
}

/// The arm's outline in a 1024 square, y down, coming in from the shoulder on the left: triceps underneath,
/// the elbow, the forearm up to the wrist, the fist, then down the inside to the biceps peak and the deltoid.
func arm() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 160, y: 735))
    curve(p, (640, 800), (320, 790), (500, 820)) // triceps
    curve(p, (770, 750), (700, 795), (750, 785)) // elbow
    curve(p, (740, 420), (810, 640), (775, 500)) // back of the forearm, tapering to the wrist
    curve(p, (792, 300), (768, 395), (797, 350)) // fist, little-finger side
    curve(p, (760, 205), (790, 255), (787, 215))
    curve(p, (598, 205), (715, 188), (650, 188)) // knuckles
    curve(p, (543, 270), (563, 210), (543, 235))
    curve(p, (560, 372), (540, 310), (545, 348)) // curled fingers
    curve(p, (610, 418), (575, 395), (595, 410)) // into the wrist
    curve(p, (600, 565), (630, 460), (625, 525)) // inside of the forearm
    curve(p, (430, 425), (585, 470), (515, 415)) // biceps peak
    curve(p, (285, 495), (360, 432), (310, 462))
    curve(p, (180, 440), (265, 470), (225, 432)) // deltoid
    curve(p, (160, 735), (40, 470), (40, 720)) // the shoulder, rounded off
    p.closeSubpath()
    return p
}

/// Where muscles meet: soft shadows in the skin.
func creases() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 340, y: 645)) // under the biceps
    curve(p, (600, 598), (430, 672), (530, 660))
    p.move(to: CGPoint(x: 287, y: 505)) // deltoid into the arm
    curve(p, (300, 590), (296, 535), (300, 565))
    p.move(to: CGPoint(x: 612, y: 592)) // elbow crease
    curve(p, (665, 665), (630, 620), (650, 645))
    return p
}

/// The fingers curled toward the viewer.
func fingers() -> CGPath {
    let p = CGMutablePath()
    for y in [250.0, 285, 320] {
        p.move(to: CGPoint(x: 550, y: y))
        curve(p, (628, y + 4), (575, y + 10), (604, y + 10))
    }
    return p
}

/// The thumb, lying across the curled fingers.
func thumb() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 556, y: 350))
    curve(p, (660, 326), (590, 330), (630, 320))
    curve(p, (668, 356), (680, 330), (682, 350))
    curve(p, (572, 380), (640, 366), (600, 382))
    curve(p, (556, 350), (560, 378), (550, 362))
    p.closeSubpath()
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
    context.drawLinearGradient(background, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: rect.width / size, y: rect.height / size)
    drawArm(context, scale: 0.95) // its whole bounding box still fits the watch's round mask
}

/// The arm centred in the 1024 square at `scale`: skin lit from the top left, soft creases, highlights on the muscles.
func drawArm(_ context: CGContext, scale: Double) {
    let box = arm().boundingBoxOfPath
    context.translateBy(x: size / 2, y: size / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.midX, y: -box.midY)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 22), blur: 44, color: CGColor(gray: 0, alpha: 0.4))
    context.addPath(arm())
    context.setFillColor(skin)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(arm())
    context.clip()
    let shading = CGGradient(colorsSpace: nil, colors: [skinLight, skin, skinShadow] as CFArray, locations: [0, 0.45, 1])!
    context.drawLinearGradient(shading, start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.maxX, y: box.maxY), options: [])
    context.setLineCap(.round)
    for width in [56.0, 34, 16] { // a soft edge from wide, faint strokes
        context.addPath(creases())
        context.setStrokeColor(skinShadow.copy(alpha: 0.12)!)
        context.setLineWidth(width)
        context.strokePath()
    }
    let shine = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    for (x, y, radius) in [(450.0, 495.0, 120.0), (190.0, 520.0, 75), (715.0, 250.0, 60)] {
        context.drawRadialGradient(shine, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
    }
    context.restoreGState()

    context.addPath(fingers())
    context.setStrokeColor(skinShadow)
    context.setLineWidth(9)
    context.setLineCap(.round)
    context.strokePath()
    context.addPath(thumb())
    context.setFillColor(skin)
    context.fillPath()
    context.addPath(thumb())
    context.setStrokeColor(skinShadow)
    context.setLineWidth(7)
    context.strokePath()
    context.addPath(arm())
    context.setStrokeColor(skinShadow.copy(alpha: 0.8)!)
    context.setLineWidth(5)
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
    context.setFillColor(darkRed)
    context.fillPath()
    context.restoreGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.clip()
    icon(context, in: rect)
}
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    write(image(mac, alpha: true, pixels: pixels), "App/Assets.xcassets/AppIcon.appiconset/mac-\(pixels).png")
}
write(image({ drawArm($0, scale: 0.95) }, alpha: true), "Design/flex-arm.png")
