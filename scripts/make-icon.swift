// Draws Cool Head's logo options as PNGs, and the app icon set.
// Usage: swift scripts/make-icon.swift <output folder> [ice|flat|line|all|sheet]
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "build/icon")
let which = args.count > 2 ? args[2] : "all"
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// The bolt, in a 1×1 box (origin bottom-left).
func bolt(in r: NSRect) -> NSBezierPath {
    let pts: [(CGFloat, CGFloat)] = [(0.62, 1.0), (0.12, 0.42), (0.46, 0.42), (0.36, 0.0), (0.88, 0.60), (0.54, 0.60)]
    let p = NSBezierPath()
    for (i, (x, y)) in pts.enumerated() {
        let pt = NSPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    p.lineJoinStyle = .round
    return p
}

/// The macOS icon grid: a rounded square inset from the canvas.
func tile(_ s: CGFloat) -> NSRect { NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8) }

/// Option 1, "Ice": a bolt frozen inside a translucent ice cube, drawn in three dimensions.
func drawIce(_ s: CGFloat) {
    let t = tile(s)
    let back = NSBezierPath(roundedRect: t, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [color(0x1B3A5C), color(0x0E2238)])!.draw(in: back, angle: -90)
    // an isometric cube: centre, half-width and edge height
    let cx = s / 2, cy = s * 0.47, w = s * 0.27, h = s * 0.30, d = w * 0.58
    let topC = NSPoint(x: cx, y: cy + h / 2 + d)            // top vertex
    let l = NSPoint(x: cx - w, y: cy + h / 2), r = NSPoint(x: cx + w, y: cy + h / 2)
    let mid = NSPoint(x: cx, y: cy + h / 2 - d)              // front vertex of the top face
    let lb = NSPoint(x: cx - w, y: cy - h / 2), rb = NSPoint(x: cx + w, y: cy - h / 2)
    let bot = NSPoint(x: cx, y: cy - h / 2 - d)
    func face(_ pts: [NSPoint]) -> NSBezierPath {
        let p = NSBezierPath(); p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }; p.close()
        p.lineJoinStyle = .round; return p
    }
    let topFace = face([topC, r, mid, l]), leftFace = face([l, mid, bot, lb]), rightFace = face([mid, r, rb, bot])
    // the bolt sits inside the ice: drawn first, then the faces over it, slightly see-through
    let bolt = bolt(in: NSRect(x: cx - w * 0.55, y: cy - h * 0.62, width: w * 1.1, height: h * 1.5))
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = color(0xFFC83D, 0.9); glow.shadowBlurRadius = s * 0.07; glow.set()
    NSGradient(colors: [color(0xFFF1A6), color(0xFFB300)])!.draw(in: bolt, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xF4FBFF, 0.55), color(0xCBEAFB, 0.45)])!.draw(in: topFace, angle: -90)
    NSGradient(colors: [color(0xA9DBF7, 0.42), color(0x6FBDEB, 0.38)])!.draw(in: leftFace, angle: -90)
    NSGradient(colors: [color(0x7CC4EE, 0.38), color(0x3C97D3, 0.34)])!.draw(in: rightFace, angle: -90)
    // the bolt shows through the front edge, a touch brighter where the ice is thinnest
    NSGraphicsContext.saveGraphicsState()
    bolt.setClip()
    color(0xFFD54F, 0.35).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()
    NSGraphicsContext.restoreGraphicsState()
    for f in [topFace, leftFace, rightFace] { f.lineWidth = s * 0.012; color(0xFFFFFF, 0.85).setStroke(); f.stroke() }
    // a frost glint on the top face
    let glint = NSBezierPath(ovalIn: NSRect(x: cx - w * 0.55, y: cy + h / 2 + d * 0.15, width: w * 0.45, height: d * 0.35))
    color(0xFFFFFF, 0.5).setFill(); glint.fill()
}

/// Option 2, "Flat": a white bolt on a cool blue tile. Reads well at small sizes.
func drawFlat(_ s: CGFloat) {
    let t = tile(s)
    let shape = NSBezierPath(roundedRect: t, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [color(0x56CCF2), color(0x2F80ED)])!.draw(in: shape, angle: -90)
    color(0xFFFFFF).setFill()
    bolt(in: t.insetBy(dx: t.width * 0.28, dy: t.height * 0.2)).fill()
}

/// Option 3, "Line": an outlined cube with the bolt as a single crack. Monochrome, minimal.
func drawLine(_ s: CGFloat) {
    let t = tile(s)
    let shape = NSBezierPath(roundedRect: t, xRadius: s * 0.18, yRadius: s * 0.18)
    color(0xF5F9FC).setFill(); shape.fill()
    let cube = NSBezierPath(roundedRect: t.insetBy(dx: t.width * 0.2, dy: t.height * 0.2), xRadius: s * 0.08, yRadius: s * 0.08)
    cube.lineWidth = s * 0.035
    color(0x1F3B57).setStroke(); cube.stroke()
    let b = bolt(in: t.insetBy(dx: t.width * 0.33, dy: t.height * 0.27))
    b.lineWidth = s * 0.03
    color(0x1F9BD7).setStroke(); b.stroke()
}

func render(_ draw: (CGFloat) -> Void, size: Int) -> Data { render(draw, width: size, height: size, scale: CGFloat(size)) }

func render(_ draw: (CGFloat) -> Void, width: Int, height: Int, scale: CGFloat = 0) -> Data {
    let size = width
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(scale > 0 ? scale : CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let options: [(String, (CGFloat) -> Void)] = [("ice", drawIce), ("flat", drawFlat), ("line", drawLine)]
for (name, draw) in options where which == "all" || which == name {
    if which == "sheet" { break }
    try! render(draw, size: 1024).write(to: out.appendingPathComponent("logo-\(name).png"))
    // the app icon set, for iconutil
    let set = out.appendingPathComponent("AppIcon-\(name).iconset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        try! render(draw, size: base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
        try! render(draw, size: base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
}
// "sheet": the three options side by side, large and at Dock and Finder sizes, on light and dark.
if which == "sheet" {
    let w = 1200, h = 760
    try! render({ _ in
        for (row, bg) in [(0, color(0xF5F5F7)), (1, color(0x1E1E1E))] {
            bg.setFill(); NSBezierPath(rect: NSRect(x: 0, y: CGFloat(h) - CGFloat(row + 1) * 380, width: CGFloat(w), height: 380)).fill()
        }
        for (i, (name, draw)) in options.enumerated() {
            let x = CGFloat(60 + i * 380)
            for row in 0..<2 {
                let top = CGFloat(h) - CGFloat(row) * 380
                // large
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform(); t.translateX(by: x, yBy: top - 300); t.scale(by: 240.0 / 1024.0); t.concat()
                draw(1024)
                NSGraphicsContext.restoreGraphicsState()
                // Dock (64) and Finder list (32) sizes
                for (j, size) in [64.0, 32.0].enumerated() {
                    NSGraphicsContext.saveGraphicsState()
                    let t2 = NSAffineTransform(); t2.translateX(by: x + 250, yBy: top - 120 - CGFloat(j) * 90); t2.scale(by: size / 1024.0); t2.concat()
                    draw(1024)
                    NSGraphicsContext.restoreGraphicsState()
                }
                let label = name.prefix(1).uppercased() + name.dropFirst()
                (label as NSString).draw(at: NSPoint(x: x + 90, y: top - 350), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                    .foregroundColor: row == 0 ? color(0x1D1D1F) : color(0xF5F5F7)])
            }
        }
    }, width: w, height: h).write(to: out.appendingPathComponent("logo-options.png"))
}
print("wrote \(out.path)")
