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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(offer.levels, id: \.self) { level in
                    Button { pick(level) } label: {
                        VStack(spacing: 5) {
                            // a symbol for how fast each stop runs, slowest to fastest (Version 2 of the renders)
                            if LimitGauge.symbols {
                                Image(systemName: LimitGauge.symbol(level))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(filled(level) ? shade(level) : Ink.muted.opacity(0.6))
                                    .frame(height: 18)
                            }
                            // bars that rise from the slowest stop to Full speed, in a blue that deepens with them,
                            // so the row reads as more and less at a glance; empty above where it is now
                            ZStack(alignment: .bottom) {
                                Color.clear.frame(height: LimitGauge.tallest)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(filled(level) ? shade(level) : Color.primary.opacity(0.12))
                                    .frame(height: height(level))
                                    // the recommended stop: a ring just outside the bar, so it shows on a filled stop too
                                    .overlay(RoundedRectangle(cornerRadius: 5)
                                        .stroke(level == offer.suggested && level != offer.current ? Ink.accent : .clear, lineWidth: 2)
                                        .padding(-4))
                            }
                            .padding(.vertical, 4)
                            Text(level.name)
                                .font(.caption.weight(level == offer.current ? .semibold : .regular))
                                .foregroundStyle(level == offer.current ? Ink.text : Ink.muted)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            if level == offer.suggested && level != offer.current {
                                Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(Ink.accent)
                            } else if level == offer.current {
                                Text("Now").font(.caption2.weight(.semibold)).foregroundStyle(Ink.muted)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { pointed = $0 ? level : (pointed == level ? nil : pointed) }
                    .accessibilityLabel(level.name)
                    .accessibilityValue(level == offer.current ? "Now" : level == offer.suggested ? "Recommended" : "")
                }
            }
            if words {
                Text((pointed ?? offer.suggested).line(before: offer.before, app: offer.app, limited: offer.current != .full))
                    .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static let tallest: CGFloat = 22
    /// For the renders: COOLHEAD_SNAPSHOT_GAUGE=symbols shows Version 2.
    static let symbols = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_GAUGE"] == "symbols"
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
