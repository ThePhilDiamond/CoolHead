import SwiftUI

/// A stone skipping across water, in a few lines, for the first look after launch (see FirstLookView): something calm to
/// watch for the 10 seconds Cool Head needs for its first full reading. Drawn with SwiftUI's Canvas rather than an
/// animation library, so it adds nothing to the app; it runs only while the first look is on screen, at most 30 frames a
/// second, and stands still with Reduce motion on. SwiftUI only, so a render script can draw its frames.
struct SkippingStoneView: View {
    var water: Color
    var stone: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { c, size in SkippingStone.draw(&c, size: size, t: SkippingStone.still, water: water, stone: stone) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    Canvas { c, size in
                        SkippingStone.draw(&c, size: size, t: tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: SkippingStone.period),
                                           water: water, stone: stone)
                    }
                }
            }
        }
        .frame(width: SkippingStone.size.width, height: SkippingStone.size.height)
        .accessibilityHidden(true)
    }
}

enum SkippingStone {
    static let size = CGSize(width: 200, height: 48)
    /// One throw, and its ripples settling, in seconds.
    static let period = 3.4
    /// The frame shown with Reduce motion on: the stone between its second and third touches, ripples behind it.
    static let still = 0.95

    /// Each hop: from x to x, how high, and how long; the first starts at the top of its arc, as if thrown.
    private struct Hop { let from: Double, to: Double, height: Double, seconds: Double, half: Bool }
    private static let hops = [Hop(from: 6, to: 58, height: 22, seconds: 0.55, half: true),
                               Hop(from: 58, to: 104, height: 15, seconds: 0.5, half: false),
                               Hop(from: 104, to: 140, height: 9, seconds: 0.4, half: false),
                               Hop(from: 140, to: 166, height: 5, seconds: 0.32, half: false),
                               Hop(from: 166, to: 182, height: 2.5, seconds: 0.25, half: false)]
    /// When and where the stone touches the water: the end of each hop.
    private static let touches: [(at: Double, x: Double)] = {
        var t = 0.0
        return hops.map { t += $0.seconds; return (t, $0.to) }
    }()
    private static let sinkSeconds = 0.2

    static func draw(_ c: inout GraphicsContext, size: CGSize, t: Double, water: Color, stone: Color) {
        let surface = size.height - 12
        // the water: one line, moving gently
        var line = Path()
        for x in stride(from: 0.0, through: size.width, by: 2) {
            let y = surface + 0.7 * sin(x / 9 + t * 2 * .pi / period)
            if x == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
        }
        c.stroke(line, with: .color(water.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        // ripples where it touched: two rings each, widening and fading
        for touch in touches {
            for lag in [0.0, 0.22] {
                let age = t - touch.at - lag
                guard age > 0 else { continue }
                let fade = max(0, 1 - age / 1.1)
                guard fade > 0 else { continue }
                let rx = 3 + 16 * age, ry = rx * 0.3
                c.stroke(Path(ellipseIn: CGRect(x: touch.x - rx, y: surface - ry, width: rx * 2, height: ry * 2)),
                         with: .color(water.opacity(0.9 * fade)), lineWidth: 1.2)
            }
        }
        // the stone: in the air on its hop, then sinking where it last touched
        var start = 0.0
        for hop in hops {
            if t < start + hop.seconds {
                let u = (t - start) / hop.seconds
                let lift = hop.half ? hop.height * (1 - u * u) : hop.height * 4 * u * (1 - u)
                drawStone(&c, x: hop.from + (hop.to - hop.from) * u, y: surface - 3 - lift, opacity: 1, color: stone)
                return
            }
            start += hop.seconds
        }
        let sinking = (t - start) / sinkSeconds
        if sinking < 1 { drawStone(&c, x: hops.last!.to, y: surface - 3 + 3 * sinking, opacity: 1 - sinking, color: stone) }
    }

    private static func drawStone(_ c: inout GraphicsContext, x: Double, y: Double, opacity: Double, color: Color) {
        var s = c
        s.translateBy(x: x, y: y)
        s.rotate(by: .degrees(-12))
        s.fill(Path(ellipseIn: CGRect(x: -3.4, y: -1.9, width: 6.8, height: 3.8)), with: .color(color.opacity(opacity)))
    }
}
