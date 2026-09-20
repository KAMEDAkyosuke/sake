// The app icon: a kikichoko seen from above -- white porcelain with the janome, the blue
// double ring every tasting cup has on its bottom.
//
//   swift assets/icon.swift --iconset <dir>     the ten sizes an .icns needs
//   swift assets/icon.swift --size 512 --out <file>   one size, for looking at a change
//
// scripts/make-icon.sh turns the first form into assets/Sake.icns.

import AppKit
import CoreGraphics

var iconsetDir: String?
var singleSize = 1024
var singleOut: String?

var args = Array(CommandLine.arguments.dropFirst())
while let arg = args.first {
    args.removeFirst()
    switch arg {
    case "--iconset": iconsetDir = args.removeFirst()
    case "--size": singleSize = Int(args.removeFirst())!
    case "--out": singleOut = args.removeFirst()
    default:
        FileHandle.standardError.write("unknown argument: \(arg)\n".data(using: .utf8)!)
        exit(2)
    }
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

func circle(_ cx: Double, _ cy: Double, _ r: Double) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2), transform: nil)
}

func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { CGFloat($0.0) })!
}

func render(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Drawn at every size rather than downscaled from one, so the rings stay crisp. The
    // coordinates below are all for a 1024 canvas.
    ctx.scaleBy(x: Double(size)/1024, y: Double(size)/1024)
    ctx.interpolationQuality = .high
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    // Shading that gives the porcelain its form at 512 is grey mush at 16, so the small
    // sizes get a fraction of it.
    let depth = size <= 32 ? 0.35 : 1.0

    let cx = 512.0, cy = 512.0
    let r = 304.0
    let indigo = rgb(23, 66, 166)

    // Apple's grid: an 824 rounded square centred on a 1024 canvas.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                       cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(58, 94, 178)), (0.5, rgb(29, 51, 118)), (1, rgb(12, 21, 56))]),
                           start: CGPoint(x: cx, y: 924), end: CGPoint(x: cx, y: 100), options: [])
    ctx.drawRadialGradient(gradient([(0, rgb(150, 195, 255, 0.20)), (1, rgb(150, 195, 255, 0))]),
                           startCenter: CGPoint(x: cx, y: cy + 60), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy + 60), endRadius: 430, options: [])

    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy - 30*depth)
    ctx.scaleBy(x: 1, y: 0.94)
    ctx.addPath(circle(0, 0, r*1.10))
    ctx.clip()
    ctx.drawRadialGradient(gradient([(0, rgb(0, 5, 22, 0.42*depth)), (0.70, rgb(0, 5, 22, 0.26*depth)),
                                     (1, rgb(0, 5, 22, 0))]),
                           startCenter: .zero, startRadius: r*0.60,
                           endCenter: .zero, endRadius: r*1.10, options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(circle(cx, cy, r))
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(255, 255, 255)), (0.62, rgb(250, 252, 255)), (1, rgb(219, 229, 245))]),
                           start: CGPoint(x: cx - r*0.65, y: cy + r*0.75),
                           end: CGPoint(x: cx + r*0.55, y: cy - r*0.85), options: [])
    ctx.setFillColor(rgb(255, 243, 200, 0.10))
    ctx.fill(canvas)
    ctx.restoreGState()

    ctx.setFillColor(indigo)
    ctx.addPath(circle(cx, cy, r*0.238))
    ctx.fillPath()
    ctx.setStrokeColor(indigo)
    ctx.setLineWidth(r*0.196)
    ctx.addPath(circle(cx, cy, r*0.590))
    ctx.strokePath()

    // The glaze catches the light on one edge only; lighting the whole face made it an eyeball.
    ctx.saveGState()
    ctx.addPath(circle(cx, cy, r))
    ctx.addPath(circle(cx, cy, r*0.945))
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(gradient([(0, rgb(255, 255, 255, 0.98*depth)),
                                     (0.55, rgb(255, 255, 255, 0.10*depth)),
                                     (1, rgb(150, 170, 205, 0.55*depth))]),
                           start: CGPoint(x: cx - r*0.72, y: cy + r*0.72),
                           end: CGPoint(x: cx + r*0.72, y: cy - r*0.72), options: [])
    ctx.restoreGState()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

if let dir = iconsetDir {
    let members: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var drawn: [Int: Data] = [:]
    for (name, size) in members {
        let png: Data
        if let cached = drawn[size] {
            png = cached
        } else {
            png = render(size: size)
            drawn[size] = png
        }
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
    print("wrote \(members.count) images to \(dir)")
} else {
    let out = singleOut ?? "icon-\(singleSize).png"
    try render(size: singleSize).write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
