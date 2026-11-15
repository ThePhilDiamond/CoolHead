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

// MARK: - Line-art ice cubes (original drawings; drawn on a 1024 canvas, scaled by `s`)

let ink = color(0x1F3B57), iceFill = color(0xFFFFFF), water = color(0x9ED8EE), amber = color(0xF5A623)

struct Iso {
    let top, l, r, mid, lb, rb, bot: NSPoint
    init(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        let d = w * 0.58
        top = NSPoint(x: cx, y: cy + h / 2 + d); l = NSPoint(x: cx - w, y: cy + h / 2); r = NSPoint(x: cx + w, y: cy + h / 2)
        mid = NSPoint(x: cx, y: cy + h / 2 - d); lb = NSPoint(x: cx - w, y: cy - h / 2); rb = NSPoint(x: cx + w, y: cy - h / 2)
        bot = NSPoint(x: cx, y: cy - h / 2 - d)
    }
    func outline() -> NSBezierPath { poly([top, r, rb, bot, lb, l]) }
}

func poly(_ pts: [NSPoint], closed: Bool = true) -> NSBezierPath {
    let p = NSBezierPath(); p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }
    if closed { p.close() }
    p.lineJoinStyle = .round; p.lineCapStyle = .round; return p
}

func stroke(_ p: NSBezierPath, _ width: CGFloat, _ c: NSColor = ink) { p.lineWidth = width; c.setStroke(); p.stroke() }

/// The front vertical edge as a lightning bolt: the ice has cracked into a bolt.
func boltEdge(_ c: Iso) -> NSBezierPath {
    let h = c.mid.y - c.bot.y, x = c.mid.x, j = h * 0.26
    return poly([c.mid, NSPoint(x: x - j, y: c.mid.y - h * 0.5), NSPoint(x: x + j, y: c.mid.y - h * 0.5), c.bot], closed: false)
}

/// A puddle under the cube: a wavy, flattened blob.
func puddle(cx: CGFloat, y: CGFloat, w: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: cx - w, y: y))
    p.curve(to: NSPoint(x: cx - w * 0.2, y: y - w * 0.22), controlPoint1: NSPoint(x: cx - w * 1.05, y: y - w * 0.2), controlPoint2: NSPoint(x: cx - w * 0.55, y: y - w * 0.12))
    p.curve(to: NSPoint(x: cx + w * 0.95, y: y - w * 0.05), controlPoint1: NSPoint(x: cx + w * 0.25, y: y - w * 0.32), controlPoint2: NSPoint(x: cx + w * 0.9, y: y - w * 0.25))
    p.curve(to: NSPoint(x: cx + w * 0.5, y: y + w * 0.16), controlPoint1: NSPoint(x: cx + w * 1.05, y: y + w * 0.08), controlPoint2: NSPoint(x: cx + w * 0.8, y: y + w * 0.16))
    p.curve(to: NSPoint(x: cx - w, y: y), controlPoint1: NSPoint(x: cx, y: y + w * 0.16), controlPoint2: NSPoint(x: cx - w * 0.85, y: y + w * 0.14))
    p.close(); p.lineJoinStyle = .round; return p
}

/// Drips running down the faces from the lower edges.
func drips(_ c: Iso, _ sw: CGFloat) {
    for (t, len) in [(0.3, 0.16), (0.72, 0.1)] as [(CGFloat, CGFloat)] {
        for (a, b) in [(c.lb, c.bot), (c.bot, c.rb)] {
            let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
            let drop = NSBezierPath(); drop.move(to: NSPoint(x: x, y: y + (c.mid.y - c.bot.y) * len)); drop.line(to: NSPoint(x: x, y: y))
            drop.lineCapStyle = .round; stroke(drop, sw * 0.9)
        }
    }
}

func lineCube(_ s: CGFloat, boltCrack: Bool, melting: Bool, glints: Bool, tileBG: Bool = true) {
    let k = s / 1024
    if tileBG {
        let t = tile(s)
        color(0xF5F9FC).setFill(); NSBezierPath(roundedRect: t, xRadius: s * 0.18, yRadius: s * 0.18).fill()
    }
    let c = Iso(cx: 512 * k, cy: (melting ? 545 : 515) * k, w: 225 * k, h: 245 * k)
    let sw = 34 * k
    if melting {
        let pd = puddle(cx: 512 * k, y: c.bot.y + 18 * k, w: 330 * k)
        water.setFill(); pd.fill(); stroke(pd, sw)
    }
    iceFill.setFill(); c.outline().fill()
    stroke(poly([c.l, c.mid, c.r], closed: false), sw)
    if boltCrack {
        stroke(boltEdge(c), sw * 1.25, amber)
    } else {
        stroke(poly([c.mid, c.bot], closed: false), sw)
    }
    if glints {
        // two short shine marks on the right face
        let ax = c.mid.x + (c.r.x - c.mid.x) * 0.45, ay = c.mid.y - (c.mid.y - c.bot.y) * 0.35
        for (i, len) in [CGFloat(70), 45].enumerated() {
            let o = CGFloat(i) * 38 * k
            stroke(poly([NSPoint(x: ax + o, y: ay - 30 * k), NSPoint(x: ax + o + len * 0.5 * k, y: ay - 30 * k + len * k)], closed: false), sw * 0.75)
        }
    }
    if melting { drips(c, sw) }
    stroke(c.outline(), sw)
}

func lerp(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint { NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }

/// The broken-line style: an outline with one gap near the top-left (where light catches the edge), a short
/// shine dash beside it, and inner edges that stop short of the outline. `clearInside` empties the cube first,
/// so a cube drawn in front hides the one behind.
func gapCube(_ c: Iso, _ sw: CGFloat, _ inkColor: NSColor, clearInside: Bool) {
    if clearInside {
        NSGraphicsContext.current?.compositingOperation = .clear
        c.outline().fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        if inkColor != .black { iceFill.setFill(); c.outline().fill() }
    }
    // outline, leaving a gap on the top-left edge between 35% and 55% of the way from l to top
    stroke(poly([lerp(c.l, c.top, 0.55), c.top, c.r, c.rb, c.bot, c.lb, c.l, lerp(c.l, c.top, 0.35)], closed: false), sw, inkColor)
    // a shine dash inside, parallel to that edge
    let inset = NSPoint(x: (c.mid.x - c.l.x) * 0.16, y: (c.mid.y - c.l.y) * 0.16)
    let a = lerp(c.l, c.top, 0.62), b = lerp(c.l, c.top, 0.82)
    stroke(poly([NSPoint(x: a.x + inset.x, y: a.y + inset.y), NSPoint(x: b.x + inset.x, y: b.y + inset.y)], closed: false), sw, inkColor)
    // inner edges, stopping short of the outline; the vertical one broken near its foot
    stroke(poly([lerp(c.mid, c.l, 0.82), c.mid, lerp(c.mid, c.r, 0.82)], closed: false), sw, inkColor)
    stroke(poly([c.mid, lerp(c.mid, c.bot, 0.55)], closed: false), sw, inkColor)
    stroke(poly([lerp(c.mid, c.bot, 0.72), lerp(c.mid, c.bot, 0.8)], closed: false), sw, inkColor)
}

func gapTile(_ s: CGFloat, pair: Bool) {
    let k = s / 1024
    color(0xF5F9FC).setFill(); NSBezierPath(roundedRect: tile(s), xRadius: s * 0.18, yRadius: s * 0.18).fill()
    if pair {
        gapCube(Iso(cx: 430 * k, cy: 560 * k, w: 190 * k, h: 205 * k), 30 * k, ink, clearInside: true)
        gapCube(Iso(cx: 640 * k, cy: 410 * k, w: 135 * k, h: 145 * k), 30 * k, ink, clearInside: true)
    } else {
        gapCube(Iso(cx: 512 * k, cy: 512 * k, w: 225 * k, h: 245 * k), 34 * k, ink, clearInside: true)
    }
}

let lineOptions: [(String, (CGFloat) -> Void)] = [
    ("cube", { lineCube($0, boltCrack: false, melting: false, glints: true) }),
    ("crack", { lineCube($0, boltCrack: true, melting: false, glints: true) }),
    ("melt", { lineCube($0, boltCrack: false, melting: true, glints: false) }),
    ("crack-melt", { lineCube($0, boltCrack: true, melting: true, glints: false) }),
    ("gap", { gapTile($0, pair: false) }),
    ("pair", { gapTile($0, pair: true) }),
]

/// A template image for the menu bar: the same drawing in one colour, no tile.
func menuTemplate(_ name: String) -> (CGFloat) -> Void {
    return { s in
        let bolt = name.contains("crack"), melt = name.contains("melt")
        let k = s / 1024
        if name == "gap" { gapCube(Iso(cx: 512 * k, cy: 512 * k, w: 330 * k, h: 360 * k), 80 * k, .black, clearInside: true); return }
        if name == "pair" {
            gapCube(Iso(cx: 400 * k, cy: 580 * k, w: 280 * k, h: 300 * k), 75 * k, .black, clearInside: true)
            gapCube(Iso(cx: 700 * k, cy: 370 * k, w: 200 * k, h: 215 * k), 75 * k, .black, clearInside: true)
            return
        }
        let c = Iso(cx: 512 * k, cy: (melt ? 560 : 512) * k, w: 330 * k, h: 360 * k)
        let sw = 90 * k
        if melt { stroke(puddle(cx: 512 * k, y: c.bot.y + 30 * k, w: 470 * k), sw * 0.8, .black) }
        // clear the cube's inside rather than filling it, so the menu bar shows lines, not a solid shape
        NSGraphicsContext.current?.compositingOperation = .clear
        c.outline().fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        stroke(poly([c.l, c.mid, c.r], closed: false), sw, .black)
        stroke(bolt ? boltEdge(c) : poly([c.mid, c.bot], closed: false), sw, .black)
        stroke(c.outline(), sw, .black)
    }
}

// MARK: - Faces: a cool head, literally (original drawings)

func arc(_ c: NSPoint, _ r: CGFloat, _ a0: CGFloat, _ a1: CGFloat, clockwise: Bool = false) -> NSBezierPath {
    let p = NSBezierPath(); p.appendArc(withCenter: c, radius: r, startAngle: a0, endAngle: a1, clockwise: clockwise)
    p.lineCapStyle = .round; return p
}

func snowflake(_ c: NSPoint, _ r: CGFloat, _ sw: CGFloat, _ col: NSColor) {
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 + .pi / 2
        let tip = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        stroke(poly([c, tip], closed: false), sw, col)
        let m = NSPoint(x: c.x + cos(a) * r * 0.6, y: c.y + sin(a) * r * 0.6)
        for side in [-1.0, 1.0] as [CGFloat] {
            let b = a + side * .pi / 4
            stroke(poly([m, NSPoint(x: m.x + cos(b) * r * 0.32, y: m.y + sin(b) * r * 0.32)], closed: false), sw, col)
        }
    }
}

/// k: scale from the 1024 canvas. line: draw as a one-colour line icon (for the menu bar).
func face(_ s: CGFloat, style: String, line: Bool = false) {
    let k = s / 1024
    let col: NSColor = line ? .black : ink
    let sw = (line ? 64 : 30) * k
    if !line {
        let bg: NSColor = style == "shades" ? color(0x5BB8E8) : color(0xEAF6FD)
        bg.setFill(); NSBezierPath(roundedRect: tile(s), xRadius: s * 0.18, yRadius: s * 0.18).fill()
    }
    let c = NSPoint(x: 512 * k, y: 490 * k), r: CGFloat = (line ? 400 : 290) * k
    let head: NSBezierPath = style == "cube"
        ? NSBezierPath(roundedRect: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), xRadius: r * 0.32, yRadius: r * 0.32)
        : NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    if !line {
        let fill: [NSColor] = style == "frosty" ? [color(0xBFE6FA), color(0x7CC7EE)]
            : style == "cube" ? [color(0xF4FBFF), color(0xA9DBF7)]
            : [color(0xFFFFFF), color(0xCDEBFA)]
        NSGradient(colors: fill)!.draw(in: head, angle: -90)
    }
    stroke(head, sw, col)
    let ex = r * 0.36, ey = c.y + r * 0.12
    switch style {
    case "shades":
        // sunglasses: two rounded lenses and a bridge
        for side in [-1.0, 1.0] as [CGFloat] {
            let lens = NSBezierPath(roundedRect: NSRect(x: c.x + side * ex - r * 0.3, y: ey - r * 0.16, width: r * 0.6, height: r * 0.34),
                                    xRadius: r * 0.12, yRadius: r * 0.12)
            if line { stroke(lens, sw, col) } else { col.setFill(); lens.fill() }
        }
        stroke(poly([NSPoint(x: c.x - r * 0.08, y: ey + r * 0.08), NSPoint(x: c.x + r * 0.08, y: ey + r * 0.08)], closed: false), sw, col)
        stroke(arc(NSPoint(x: c.x + r * 0.05, y: c.y - r * 0.12), r * 0.32, 215, 320), sw, col)    // a relaxed half smile
    case "frosty":
        // frost along the top of the head: a scalloped cap with icicles
        if !line {
            let cap = NSBezierPath()
            cap.appendArc(withCenter: c, radius: r, startAngle: 20, endAngle: 160)
            var x = c.x - r * 0.94
            let y0 = c.y + r * 0.34
            cap.line(to: NSPoint(x: x, y: y0))
            var i = 0
            while x < c.x + r * 0.94 {
                let w = r * 0.235, drop: CGFloat = i % 2 == 0 ? r * 0.2 : r * 0.1
                cap.curve(to: NSPoint(x: x + w, y: y0), controlPoint1: NSPoint(x: x + w * 0.2, y: y0 - drop), controlPoint2: NSPoint(x: x + w * 0.8, y: y0 - drop))
                x += w; i += 1
            }
            cap.close()
            iceFill.setFill(); cap.fill(); stroke(cap, sw * 0.8, col)
        } else {
            stroke(poly([NSPoint(x: c.x - r * 0.8, y: c.y + r * 0.4), NSPoint(x: c.x + r * 0.8, y: c.y + r * 0.4)], closed: false), sw * 0.8, col)
        }
        for side in [-1.0, 1.0] as [CGFloat] {      // happy eyes, closed in a smile
            stroke(arc(NSPoint(x: c.x + side * ex, y: ey - r * 0.12), r * 0.13, 20, 160), sw, col)
        }
        stroke(arc(NSPoint(x: c.x, y: c.y - r * 0.1), r * 0.42, 205, 335), sw, col)
    case "cube":
        for side in [-1.0, 1.0] as [CGFloat] {
            let eye = NSBezierPath(ovalIn: NSRect(x: c.x + side * ex - r * 0.07, y: ey - r * 0.07, width: r * 0.14, height: r * 0.16))
            col.setFill(); eye.fill()
        }
        stroke(arc(NSPoint(x: c.x, y: c.y - r * 0.02), r * 0.3, 215, 325), sw, col)
        if !line {     // a shine on the ice
            stroke(arc(NSPoint(x: c.x, y: c.y), r * 0.78, 115, 150), sw * 0.8, color(0xFFFFFF))
        }
    case "snowflake-mind":
        // calm closed eyes and a smile, with a snowflake where the thoughts are
        for side in [-1.0, 1.0] as [CGFloat] {
            stroke(arc(NSPoint(x: c.x + side * ex, y: ey + r * 0.02), r * 0.13, 200, 340), sw, col)
        }
        stroke(arc(NSPoint(x: c.x, y: c.y - r * 0.06), r * 0.36, 215, 325), sw, col)
        snowflake(NSPoint(x: c.x, y: c.y + r * 0.6), r * 0.2, sw * 0.7, line ? col : color(0x2E9BD6))
    default: // "calm": eyes closed in contentment, a small smile
        for side in [-1.0, 1.0] as [CGFloat] {
            stroke(arc(NSPoint(x: c.x + side * ex, y: ey + r * 0.02), r * 0.13, 200, 340), sw, col)
        }
        stroke(arc(NSPoint(x: c.x, y: c.y - r * 0.06), r * 0.36, 215, 325), sw, col)
    }
}

/// A snowflake drawn as white lines with a dark edge, so it shows on any colour.
func outlinedFlake(_ c: NSPoint, _ r: CGFloat, _ sw: CGFloat, line: Bool) {
    if line { snowflake(c, r, sw, .black); return }
    snowflake(c, r, sw * 1.9, ink)
    snowflake(c, r, sw, color(0xFFFFFF))
}

/// Round 2 of faces: a blue smiley, with icicles, snowflake "sweat", snowflakes behind, or made of the letters C and H.
func face2(_ s: CGFloat, style: String, line: Bool = false) {
    let k = s / 1024
    let col: NSColor = line ? .black : ink
    let sw = (line ? 64 : 30) * k
    let c = NSPoint(x: 512 * k, y: (style == "sweat" ? 470 : 500) * k)
    let r: CGFloat = (line ? 380 : (style == "sweat" ? 270 : 290)) * k
    if !line {
        let bg: [NSColor] = style == "flurry" ? [color(0x6CC4F0), color(0x2F86D0)] : [color(0xEAF6FD), color(0xD7EEFB)]
        NSGradient(colors: bg)!.draw(in: NSBezierPath(roundedRect: tile(s), xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)
        if style == "flurry" {
            for (x, y, rr) in [(250.0, 800.0, 55.0), (790.0, 820.0, 40.0), (830.0, 300.0, 50.0), (205.0, 330.0, 35.0), (700.0, 180.0, 30.0)] as [(CGFloat, CGFloat, CGFloat)] {
                snowflake(NSPoint(x: x * k, y: y * k), rr * k, 12 * k, color(0xFFFFFF, 0.85))
            }
        }
    } else if style == "flurry" {
        snowflake(NSPoint(x: 120 * k, y: 900 * k), 90 * k, 40 * k, .black)
    }
    let head = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    if style == "ch" {
        // the C is the head: an open circle, its gap on the right
        stroke(arc(c, r, 40, 320), sw * 1.5, col)
        // the H is the face: its legs are the eyes, its bar a smile between them
        let ex = r * 0.34, top = c.y + r * 0.36, bottom = c.y - r * 0.12
        for side in [-1.0, 1.0] as [CGFloat] {
            stroke(poly([NSPoint(x: c.x + side * ex, y: top), NSPoint(x: c.x + side * ex, y: bottom)], closed: false), sw * 1.5, col)
        }
        let smile = NSBezierPath(); smile.move(to: NSPoint(x: c.x - ex, y: c.y + r * 0.12))
        smile.curve(to: NSPoint(x: c.x + ex, y: c.y + r * 0.12), controlPoint1: NSPoint(x: c.x - ex * 0.5, y: c.y - r * 0.12), controlPoint2: NSPoint(x: c.x + ex * 0.5, y: c.y - r * 0.12))
        smile.lineCapStyle = .round
        stroke(smile, sw * 1.5, line ? col : color(0x2E9BD6))
        return
    }
    if !line {
        NSGradient(colors: style == "flurry" ? [color(0xFFFFFF), color(0xD9F0FC)] : [color(0x9BD8F6), color(0x4DB2E6)])!.draw(in: head, angle: -90)
    }
    if style == "icicles" {
        // a frozen band across the top of the head, with pointed icicles hanging from it
        NSGraphicsContext.saveGraphicsState()
        head.addClip()
        let y0 = c.y + r * 0.42
        let ice = NSBezierPath()
        ice.move(to: NSPoint(x: c.x - r, y: c.y + r))
        ice.line(to: NSPoint(x: c.x - r, y: y0))
        let n = 7
        for i in 0..<n {
            let x0 = c.x - r + CGFloat(i) * 2 * r / CGFloat(n), x1 = x0 + 2 * r / CGFloat(n)
            let len: CGFloat = [0.22, 0.12, 0.3, 0.15, 0.26, 0.1, 0.2][i] * r
            ice.line(to: NSPoint(x: (x0 + x1) / 2, y: y0 - len))
            ice.line(to: NSPoint(x: x1, y: y0))
        }
        ice.line(to: NSPoint(x: c.x + r, y: c.y + r)); ice.close(); ice.lineJoinStyle = .round
        if line { stroke(ice, sw * 0.7, col) } else { color(0xFFFFFF).setFill(); ice.fill(); stroke(ice, sw * 0.6, col) }
        NSGraphicsContext.restoreGraphicsState()
    }
    stroke(head, sw, col)
    // happy eyes and a wide smile
    let ex = r * 0.34, ey = c.y + (style == "icicles" ? r * 0.02 : r * 0.12)
    for side in [-1.0, 1.0] as [CGFloat] {
        stroke(arc(NSPoint(x: c.x + side * ex, y: ey - r * 0.1), r * 0.12, 20, 160), sw, col)
    }
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: c.x - r * 0.42, y: c.y - r * 0.2))
    mouth.curve(to: NSPoint(x: c.x + r * 0.42, y: c.y - r * 0.2), controlPoint1: NSPoint(x: c.x - r * 0.25, y: c.y - r * 0.62), controlPoint2: NSPoint(x: c.x + r * 0.25, y: c.y - r * 0.62))
    mouth.close()
    if line { stroke(mouth, sw, col) } else { color(0xFFFFFF).setFill(); mouth.fill(); stroke(mouth, sw, col) }
    if style == "sweat" {
        // snowflakes where sweat drops would be: hot work, kept cool
        outlinedFlake(NSPoint(x: c.x + r * 0.95, y: c.y + r * 0.85), r * 0.28, sw * 0.7, line: line)
        if !line { outlinedFlake(NSPoint(x: c.x + r * 1.18, y: c.y + r * 0.32), r * 0.16, sw * 0.55, line: false) }
    }
}

let face2Options = ["icicles", "sweat", "flurry", "ch"]

let faceOptions = ["calm", "snowflake-mind", "frosty", "shades", "cube"]

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
    if ["sheet", "linesheet", "facesheet", "facesheet2"].contains(which) { break }
    try! render(draw, size: 1024).write(to: out.appendingPathComponent("logo-\(name).png"))
    // the app icon set, for iconutil
    let set = out.appendingPathComponent("AppIcon-\(name).iconset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        try! render(draw, size: base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
        try! render(draw, size: base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
}
// "facesheet": the face ideas, large, at Dock and Finder sizes, and as the menu bar icon, on light and dark.
if which == "facesheet" || which == "facesheet2" {
    let second = which == "facesheet2"
    let names = second ? face2Options : faceOptions
    func drawFace(_ s: CGFloat, _ style: String, _ line: Bool) { second ? face2(s, style: style, line: line) : face(s, style: style, line: line) }
    let n = names.count, w = 40 + n * 380, h = 820
    try! render({ _ in
        for (row, bg) in [(0, color(0xF5F5F7)), (1, color(0x1E1E1E))] {
            bg.setFill(); NSBezierPath(rect: NSRect(x: 0, y: CGFloat(h) - CGFloat(row + 1) * 410, width: CGFloat(w), height: 410)).fill()
        }
        for (i, style) in names.enumerated() {
            let x = CGFloat(40 + i * 380)
            for row in 0..<2 {
                let top = CGFloat(h) - CGFloat(row) * 410
                func place(_ px: CGFloat, _ py: CGFloat, _ size: CGFloat, line: Bool) {
                    NSGraphicsContext.saveGraphicsState()
                    let t = NSAffineTransform(); t.translateX(by: px, yBy: py); t.scale(by: size / 1024.0); t.concat()
                    if line {
                        let img = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in drawFace(1024, style, true); return true }
                        let tinted = NSImage(size: img.size, flipped: false) { r in img.draw(in: r); (row == 0 ? NSColor.black : NSColor.white).set(); r.fill(using: .sourceAtop); return true }
                        tinted.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
                    } else { drawFace(1024, style, false) }
                    NSGraphicsContext.restoreGraphicsState()
                }
                place(x, top - 300, 240, line: false)
                place(x + 250, top - 110, 64, line: false)
                place(x + 266, top - 170, 32, line: false)
                let bar = NSRect(x: x + 240, y: top - 260, width: 84, height: 48)
                (row == 0 ? color(0xE8E8EA) : color(0x2C2C2E)).setFill(); NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()
                place(x + 264, top - 254, 36, line: true)
                let label = (second ? ["Icicles", "Snowflake sweat", "Snowflakes behind", "C + H"] : ["Calm", "Snowflake mind", "Frosty", "Shades", "Ice cube face"])[i]
                (label as NSString).draw(at: NSPoint(x: x + 20, y: top - 360), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                    .foregroundColor: row == 0 ? color(0x1D1D1F) : color(0xF5F5F7)])
            }
        }
    }, width: w, height: h).write(to: out.appendingPathComponent(second ? "logo-face-options-2.png" : "logo-face-options.png"))
}

// "linesheet": the four line-art cubes, large, at Dock and Finder sizes, and as the menu bar icon, on light and dark.
if which == "linesheet" {
    let w = 2320, h = 820
    try! render({ _ in
        for (row, bg) in [(0, color(0xF5F5F7)), (1, color(0x1E1E1E))] {
            bg.setFill(); NSBezierPath(rect: NSRect(x: 0, y: CGFloat(h) - CGFloat(row + 1) * 410, width: CGFloat(w), height: 410)).fill()
        }
        for (i, (name, draw)) in lineOptions.enumerated() {
            let x = CGFloat(40 + i * 380)
            for row in 0..<2 {
                let top = CGFloat(h) - CGFloat(row) * 410
                func place(_ d: (CGFloat) -> Void, _ px: CGFloat, _ py: CGFloat, _ size: CGFloat) {
                    NSGraphicsContext.saveGraphicsState()
                    let t = NSAffineTransform(); t.translateX(by: px, yBy: py); t.scale(by: size / 1024.0); t.concat()
                    d(1024); NSGraphicsContext.restoreGraphicsState()
                }
                place(draw, x, top - 300, 240)
                place(draw, x + 250, top - 110, 64)
                place(draw, x + 266, top - 170, 32)
                // the menu bar icon at its real size (18 points, drawn at 2x), in the menu bar's colour
                let bar = NSRect(x: x + 240, y: top - 260, width: 84, height: 48)
                (row == 0 ? color(0xE8E8EA) : color(0x2C2C2E)).setFill(); NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform(); t.translateX(by: x + 264, yBy: top - 254); t.scale(by: 36.0 / 1024.0); t.concat()
                if row == 1 {
                    // white glyph on a dark bar: draw the template, then recolour by drawing with a light ink
                    let img = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in menuTemplate(name)(1024); return true }
                    let tinted = NSImage(size: img.size, flipped: false) { r in
                        img.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
                    tinted.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
                } else {
                    let img = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in menuTemplate(name)(1024); return true }
                    let tinted = NSImage(size: img.size, flipped: false) { r in
                        img.draw(in: r); NSColor.black.set(); r.fill(using: .sourceAtop); return true }
                    tinted.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
                }
                NSGraphicsContext.restoreGraphicsState()
                let label = ["Cube", "Crack", "Melt", "Crack and melt", "Gap", "Pair"][i]
                (label as NSString).draw(at: NSPoint(x: x + 20, y: top - 360), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                    .foregroundColor: row == 0 ? color(0x1D1D1F) : color(0xF5F5F7)])
            }
        }
    }, width: w, height: h).write(to: out.appendingPathComponent("logo-line-options.png"))
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
