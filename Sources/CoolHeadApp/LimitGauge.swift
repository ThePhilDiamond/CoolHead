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
                            RoundedRectangle(cornerRadius: 4)
                                .fill(filled(level) ? Ink.fill : Color.primary.opacity(0.12))
                                .frame(height: 12)
                                // the recommended stop: a ring just outside the bar, so it shows on a filled stop too
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(level == offer.suggested && level != offer.current ? Ink.accent : .clear, lineWidth: 2)
                                    .padding(-4))
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

    /// Filled from the slowest up to where it is now.
    func filled(_ l: CPUCap.Level) -> Bool {
        (offer.levels.firstIndex(of: l) ?? 0) <= (offer.levels.firstIndex(of: offer.current) ?? 0)
    }
}
