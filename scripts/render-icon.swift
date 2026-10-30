// Render the app-icon layers from the geometry in assets/mark.svg.
// Usage: swift scripts/render-icon.swift [out-dir]   (default assets/icon/AppIcon.icon/Assets)
// Writes, both 1024x1024, for the Icon Composer package assets/icon/AppIcon.icon:
//   icon-backing.png   full-bleed navy backing
//   icon-mark.png      transparent "line cube" mark
// build-app.sh compiles the package with actool. Drawn with CoreGraphics
// rather than an SVG rasterizer, since none is installed by default.
import AppKit

let size = 1024
let unit = CGFloat(size) / 24          // the SVG's 24-unit grid
let markScale: CGFloat = 0.8           // the SVG's translate(2.4 2.4) scale(0.8)

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let backing = color(0x0C1A2B), mark = color(0xE9EEF5), accent = color(0x3BD48A)

func render(_ name: String, in dir: URL, draw: (CGContext) -> Void) throws {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // SVG coordinates: origin top-left, y down, 24 units across.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: unit, y: -unit)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
}

func stroke(_ ctx: CGContext, _ points: [[CGFloat]], close: Bool = false, width: CGFloat, _ c: CGColor) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: points[0][0], y: points[0][1]))
    for p in points.dropFirst() { ctx.addLine(to: CGPoint(x: p[0], y: p[1])) }
    if close { ctx.closePath() }
    ctx.setStrokeColor(c)
    ctx.setLineWidth(width)
    ctx.setLineCap(.butt)
    ctx.setLineJoin(.miter)
    ctx.strokePath()
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "assets/icon/AppIcon.icon/Assets")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

try render("icon-backing.png", in: out) { ctx in
    ctx.setFillColor(backing)
    ctx.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
}

try render("icon-mark.png", in: out) { ctx in
    ctx.translateBy(x: 2.4, y: 2.4)
    ctx.scaleBy(x: markScale, y: markScale)
    // The cube's outline.
    stroke(ctx, [[12, 5], [18.06, 8.5], [18.06, 15.5], [12, 19], [5.94, 15.5], [5.94, 8.5]],
           close: true, width: 0.95, mark)
    // The route: in at the bottom, up the inner edge, split at the center, out past both top corners.
    stroke(ctx, [[12, 22.6], [12, 12], [5.94, 8.5], [2.9, 6.75]], width: 1.1, accent)
    stroke(ctx, [[12, 12], [18.06, 8.5], [21.1, 6.75]], width: 1.1, accent)
}
print("Wrote icon-backing.png and icon-mark.png to \(out.path)")
