// Builds the app icons from Design/icon-source.jpg, a rounded square on a light margin. Run from the repo root: swift Design/Icon.swift
// iPhone and watch get the square's art full bleed with its corners filled in its own color, since they cut their own
// shape; the Mac gets the inset rounded square macOS icons are, and so does Design/icon.png for the README.
import CoreGraphics
import Foundation
import ImageIO

let source = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(filePath: "Design/icon-source.jpg") as CFURL, nil)!, 0, nil)!
let (width, height) = (source.width, source.height)
let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
func rgb(_ x: Int, _ y: Int) -> [Int] { (0..<3).map { Int(pixels[(y * width + x) * 4 + $0]) } } // y counts from the top
func margin(_ x: Int, _ y: Int) -> Bool { rgb(x, y).reduce(0, +) > 600 }

// The square: where the margin ends on the middle row and column, and the corner radius from where it ends on each
// corner's diagonal. The largest corner, with some to spare, covers corners that aren't quite alike.
let left = (0..<width).first { !margin($0, height / 2) }!, right = (0..<width).last { !margin($0, height / 2) }!
let top = (0..<height).first { !margin(width / 2, $0) }!, bottom = (0..<height).last { !margin(width / 2, $0) }!
let corners = [(left, top, 1, 1), (right, top, -1, 1), (left, bottom, 1, -1), (right, bottom, -1, -1)].map { x, y, dx, dy in
    Double((0..<width).first { !margin(x + dx * $0, y + dy * $0) }!) / (1 - 1 / 2.squareRoot())
}
let radius = corners.max()! * 1.15
let patch = (0..<10).flatMap { dy in (0..<10).map { rgb(left + 20 + $0, height / 2 + dy) } }
let color = CGColor(srgbRed: Double(patch.map { $0[0] }.reduce(0, +)) / 25500, green: Double(patch.map { $0[1] }.reduce(0, +)) / 25500,
                    blue: Double(patch.map { $0[2] }.reduce(0, +)) / 25500, alpha: 1)
let square = source.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))!
print("square \(left)…\(right) × \(top)…\(bottom), corners \(corners.map(Int.init))")

/// The square's art filling `rect`, its rounded corners (and their soft edge) painted over in its color.
func fullBleed(_ context: CGContext, in rect: CGRect) {
    let scale = rect.width / Double(square.width), edge = 8 * scale
    context.setFillColor(color)
    context.fill(rect)
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect.insetBy(dx: edge, dy: edge), cornerWidth: radius * scale - edge, cornerHeight: radius * scale - edge, transform: nil))
    context.clip()
    context.draw(square, in: rect)
    context.restoreGState()
}

/// The macOS icon shape: a rounded square of 824 in 1024, with room for its shadow.
func mac(_ context: CGContext, size: Double) {
    let rect = CGRect(x: size * 100 / 1024, y: size * 100 / 1024, width: size * 824 / 1024, height: size * 824 / 1024)
    let shape = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 12 / 1024), blur: size * 28 / 1024, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(color)
    context.fillPath()
    context.restoreGState()
    context.addPath(shape)
    context.clip()
    fullBleed(context, in: rect)
}

func write(_ size: Int, alpha: Bool, to path: String, _ draw: (CGContext, Double) -> Void) {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    draw(context, Double(size))
    let destination = CGImageDestinationCreateWithURL(URL(filePath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

for path in ["App/Assets.xcassets/AppIcon.appiconset/icon.png", "Watch/Assets.xcassets/AppIcon.appiconset/icon.png"] {
    write(1024, alpha: false, to: path) { fullBleed($0, in: CGRect(x: 0, y: 0, width: $1, height: $1)) }
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
    write(size, alpha: true, to: "App/Assets.xcassets/AppIcon.appiconset/mac-\(size).png", mac)
}
write(512, alpha: true, to: "Design/icon.png", mac)
