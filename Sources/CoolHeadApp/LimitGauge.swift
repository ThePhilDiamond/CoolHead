import CoolHeadCore
import SwiftUI

/// The CPU limit as a row of stops, slowest on the left and Full speed on the right, filled up to where it is now, like
/// a speed bar: one click moves it either way. Stepped, not a slider: each stop is a named level (see CPUCap.Level).
/// The recommended stop has a ring; under the row, what the pointed-at stop does, or the recommended one's.
struct LimitGauge: View {
    let offer: CPUCap.Offer
    /// Whether to say what each level does under the row (on a card; the Managed by Cool Head line has its own words).
    var words = true
    let pick: (CPUCap.Level) -> Void
    @State private var pointed: CPUCap.Level?

    var barsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(offer.levels, id: \.self) { level in
                    Button { pick(level) } label: {
                        VStack(spacing: 5) {
                            // a symbol for how fast each stop runs, slowest to fastest (Version 2 of the renders)
                            if LimitGauge.symbols {
                                Image(systemName: LimitGauge.symbol(level))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(LimitGauge.strongSymbols ? (filled(level) ? Ink.text : Ink.muted) : filled(level) ? shade(level) : Ink.muted.opacity(0.6))
                                    .frame(height: 18)
                            }
                            // bars that rise from the slowest stop to Full speed, in a blue that deepens with them,
                            // so the row reads as more and less at a glance; empty above where it is now
                            ZStack(alignment: .bottom) {
                                Color.clear.frame(height: LimitGauge.tallest)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(filled(level) ? shade(level) : Color.primary.opacity(0.12))
                                    .frame(height: height(level))
                            }
                            .padding(.vertical, 4)
                            Text(level.name)
                                .font(.caption.weight(level == offer.current ? .semibold : .regular))
                                .foregroundStyle(level == offer.current ? Ink.text : Ink.muted)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { pointed = $0 ? level : (pointed == level ? nil : pointed) }
                    .accessibilityLabel(level.name)
                    .accessibilityValue(level == offer.current ? "Selected" : "")
                }
            }
            if words { advice }
        }
    }

    /// For the renders: COOLHEAD_SNAPSHOT_GAUGE picks the version (bars, symbols, slider, segments, or pills).
    static let version = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_GAUGE"] ?? "bars"

    var body: some View {
        switch LimitGauge.version {
        case "slider": sliderBody
        case "slider2": slider2Body
        case "bars2": barsBody
        case "dial": dialBody
        case "segments": segmentsBody
        case "pills": pillsBody
        default: barsBody
        }
    }

    /// What the chosen or recommended stop does, under any version.
    var wordsLine: some View {
        Text((pointed ?? offer.suggested).line(before: offer.before, app: offer.app, limited: offer.current != .full))
            .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
    }
    /// The recommendation as text only, with what it does: the control itself shows only where it is now, since a
    /// move takes effect at once. Once it's at the recommended stop, what that stop does.
    var advice: some View {
        let limited = offer.current != .full
        return Group {
            if offer.suggested != offer.current {
                (Text("Recommended: \(offer.suggested.name), ").fontWeight(.semibold).foregroundColor(Ink.accent)
                 + Text(offer.suggested.effect(before: offer.before, app: offer.app, limited: limited)).foregroundColor(Ink.muted))
            } else {
                Text(offer.current.line(before: offer.before, app: offer.app, limited: limited)).foregroundColor(Ink.muted)
            }
        }
        .font(.caption).fixedSize(horizontal: false, vertical: true)
    }
    var recommendedLine: some View {
        HStack(spacing: 4) {
            Text("Now: \(offer.current.name)").foregroundStyle(Ink.muted)
            if offer.suggested != offer.current {
                Text("·").foregroundStyle(Ink.muted)
                Text("Recommended: \(offer.suggested.name)").foregroundStyle(Ink.accent).fontWeight(.semibold)
            }
        }
        .font(.caption)
    }

    /// Version: macOS's own slider, stopping only at the levels' tick marks, a tortoise at the slow end and a hare at
    /// the fast end (Apple: tick marks help people land on a value; the track is untinted with them).
    var sliderBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: Binding(get: { Double(offer.levels.firstIndex(of: offer.current) ?? 0) },
                                  set: { pick(offer.levels[Int($0.rounded())]) }),
                   in: 0...Double(offer.levels.count - 1), step: 1) {
                Text("Limit")
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill").foregroundStyle(Ink.muted)
            } maximumValueLabel: {
                Image(systemName: "hare.fill").foregroundStyle(Ink.muted)
            }
            .labelsHidden()
            // each name under its tick: the track runs between the two symbols, about 24 points in from each side
            GeometryReader { g in
                let inset: CGFloat = 33, n = CGFloat(max(offer.levels.count - 1, 1))
                ForEach(Array(offer.levels.enumerated()), id: \.element) { i, l in
                    Text(l.name).font(.caption2.weight(l == offer.current ? .semibold : .regular))
                        .foregroundStyle(l == offer.suggested && l != offer.current ? Ink.accent : l == offer.current ? Ink.text : Ink.muted)
                        .multilineTextAlignment(.center).frame(width: 78)
                        .position(x: inset + (g.size.width - 2 * inset) * CGFloat(i) / n, y: 14)
                }
            }
            .frame(height: 30)
            recommendedLine
            wordsLine
        }
    }

    /// Version: macOS's segmented control, each stop a symbol over its name (Apple: for closely related choices that
    /// change a setting).
    var segmentsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Limit", selection: Binding(get: { offer.current }, set: { pick($0) })) {
                ForEach(offer.levels, id: \.self) { l in
                    Label(l.name, systemImage: LimitGauge.symbol(l)).tag(l)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            recommendedLine
            wordsLine
        }
    }

    /// Version: a row of buttons, the current one filled, the recommended one outlined in blue.
    var pillsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(offer.levels, id: \.self) { l in
                    Button { pick(l) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: LimitGauge.symbol(l)).font(.system(size: 14, weight: .semibold))
                            Text(l.name).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .foregroundStyle(l == offer.current ? Ink.onFill : Ink.text)
                        .background(l == offer.current ? Ink.fill : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(l == offer.suggested && l != offer.current ? Ink.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .onHover { pointed = $0 ? l : (pointed == l ? nil : pointed) }
                }
            }
            recommendedLine
            wordsLine
        }
    }

    /// Round 5: the slider, with the current stop named in a tag over the thumb, and the end symbols at full contrast.
    var slider2Body: some View {
        let n = CGFloat(max(offer.levels.count - 1, 1)), at = CGFloat(offer.levels.firstIndex(of: offer.current) ?? 0)
        return VStack(alignment: .leading, spacing: 4) {
            // the tag over the thumb: where it is now, in the deep blue, with a small point down to the thumb
            GeometryReader { g in
                let inset: CGFloat = 51
                VStack(spacing: 0) {
                    Text(offer.current.name).font(.caption.weight(.semibold)).foregroundStyle(Ink.onFill)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Ink.fill, in: Capsule())
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7)).foregroundStyle(Ink.fill).offset(y: -2)
                }
                .fixedSize()
                .position(x: min(max(inset + (g.size.width - 2 * inset) * at / n, 50), g.size.width - 50), y: 14)
            }
            .frame(height: 28)
            Slider(value: Binding(get: { Double(at) }, set: { pick(offer.levels[Int($0.rounded())]) }),
                   in: 0...Double(offer.levels.count - 1), step: 1) {
                Text("Limit")
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Ink.text)
            } maximumValueLabel: {
                Image(systemName: "hare.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Ink.text)
            }
            .labelsHidden()
            GeometryReader { g in
                let inset: CGFloat = 51
                ForEach(Array(offer.levels.enumerated()), id: \.element) { i, l in
                    Text(l.name).font(.caption2).foregroundStyle(Ink.muted)
                        .multilineTextAlignment(.center).frame(width: 78)
                        .position(x: inset + (g.size.width - 2 * inset) * CGFloat(i) / n, y: 14)
                }
            }
            .frame(height: 30)
            advice
        }
    }

    /// Round 5: a dial like a speedometer, slowest on the left, Full speed on the right, its needle at where it is
    /// now; each stretch of the arc is a stop to click, in the blue that strengthens toward Full speed.
    var dialBody: some View {
        let count = offer.levels.count
        return VStack(spacing: 6) {
            ZStack {
                ForEach(Array(offer.levels.enumerated()), id: \.element) { i, l in
                    let a0 = 180.0 + 180.0 * Double(i) / Double(count) + 1.5, a1 = 180.0 + 180.0 * Double(i + 1) / Double(count) - 1.5
                    DialArc(from: a0, to: a1)
                        .stroke(filled(l) ? shade(l) : Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                        .contentShape(DialArc(from: a0, to: a1).stroke(style: StrokeStyle(lineWidth: 26)))
                        .onTapGesture { pick(l) }
                }
                // the needle, to the middle of where it is now
                let at = Double(offer.levels.firstIndex(of: offer.current) ?? 0)
                DialNeedle(angle: 180 + 180 * (at + 0.5) / Double(count))
                    .stroke(Ink.text, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Circle().fill(Ink.text).frame(width: 9, height: 9).offset(y: 40)
                Text(offer.current.name).font(.callout.weight(.semibold))
                    .offset(y: 60)
                Image(systemName: "tortoise.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.text).offset(x: -114, y: 36)
                Image(systemName: "hare.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.text).offset(x: 114, y: 36)
            }
            .frame(width: 260, height: 150)
            .frame(maxWidth: .infinity)
            advice
        }
    }

    static let tallest: CGFloat = 22
    /// For the renders: COOLHEAD_SNAPSHOT_GAUGE=symbols shows Version 2.
    static let symbols = version == "symbols" || version == "bars2"
    /// Round 5: symbols at full contrast, the filled ones in the text color.
    static let strongSymbols = version == "bars2"
    static func symbol(_ l: CPUCap.Level) -> String {
        switch l {
        case .barely: return "tortoise.fill"
        case .steady: return "figure.walk"
        case .half: return "figure.run"
        case .full: return "hare.fill"
        }
    }
    /// Where a stop sits from slowest (0) to Full speed (1).
    func step(_ l: CPUCap.Level) -> CGFloat {
        let i = offer.levels.firstIndex(of: l) ?? 0
        return offer.levels.count > 1 ? CGFloat(i) / CGFloat(offer.levels.count - 1) : 1
    }
    /// From a quarter of the tallest to all of it.
    func height(_ l: CPUCap.Level) -> CGFloat { LimitGauge.tallest * (0.25 + 0.75 * step(l)) }
    /// One blue that strengthens toward Full speed: pale to the deep blue in light mode; in dark mode its own steps,
    /// dim to bright, since a faded deep blue only gets darker on a dark card.
    func shade(_ l: CPUCap.Level) -> Color {
        let t = step(l)
        return Color(nsColor: NSColor(name: nil) { a in
            let dark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let from = dark ? LimitGauge.rgb(0x2F5A93) : LimitGauge.rgb(0xA9C8F0)
            let to = dark ? LimitGauge.rgb(0x4A9EFF) : LimitGauge.rgb(0x0F52AD)
            return from.blended(withFraction: t, of: to) ?? to
        })
    }
    static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Filled from the slowest up to where it is now.
    func filled(_ l: CPUCap.Level) -> Bool {
        (offer.levels.firstIndex(of: l) ?? 0) <= (offer.levels.firstIndex(of: offer.current) ?? 0)
    }
}

/// A stretch of the dial's arc, in degrees (180 is the left end, 360 the right), centred low in its frame.
struct DialArc: Shape {
    var from: Double, to: Double
    /// How far outside the arc's middle line, for the recommended stop's ring.
    var outward: CGFloat = 0
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.minY + 115), radius = 90 + outward
        p.addArc(center: c, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        return p
    }
}

/// The dial's needle, from its centre toward the arc.
struct DialNeedle: Shape {
    var angle: Double
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.minY + 115), a = angle * .pi / 180
        var p = Path()
        p.move(to: c)
        p.addLine(to: CGPoint(x: c.x + 70 * cos(a), y: c.y + 70 * sin(a)))
        return p
    }
}
