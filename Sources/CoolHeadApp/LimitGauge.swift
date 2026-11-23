import CoolHeadCore
import SwiftUI

/// The CPU limit's control: macOS's own slider, stopping only at the levels (CPUCap.Level), slowest on the left with a
/// tortoise and Full speed on the right with a hare; Cooler, just before it, is Run it cooler with no limit. A move takes effect at once, so where it is now and what's chosen
/// are one thing, named in a tag over the thumb; the recommendation is text under it, never marked on the slider.
/// Chosen over bars, a dial, segments, and buttons after six rounds of renders (notes/cpu-cap.md).
struct LimitGauge: View {
    let offer: CPUCap.Offer
    /// Whether to say the recommendation and what it does under the slider (on a card; the Managed by Cool Head line
    /// has its own words).
    var words = true
    let pick: (CPUCap.Level) -> Void

    /// How far in from each side the slider's first and last stops sit, past the tortoise and the hare.
    static let inset: CGFloat = 51

    var body: some View {
        let n = CGFloat(max(offer.levels.count - 1, 1)), at = CGFloat(offer.levels.firstIndex(of: offer.current) ?? 0)
        VStack(alignment: .leading, spacing: 4) {
            // the tag over the thumb: where it is now, in the deep blue, with a small point down to the thumb
            GeometryReader { g in
                VStack(spacing: 0) {
                    Text(offer.current.name).font(.caption.weight(.semibold)).foregroundStyle(Ink.onFill)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Ink.fill, in: Capsule())
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7)).foregroundStyle(Ink.fill).offset(y: -2)
                }
                .fixedSize()
                .position(x: min(max(Self.inset + (g.size.width - 2 * Self.inset) * at / n, 50), g.size.width - 50), y: 14)
            }
            .frame(height: 28)
            .accessibilityHidden(true)
            Slider(value: Binding(get: { Double(at) }, set: { pick(offer.levels[Int($0.rounded())]) }),
                   in: 0...Double(offer.levels.count - 1), step: 1) {
                Text("Limit")
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Ink.text)
            } maximumValueLabel: {
                Image(systemName: "hare.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Ink.text)
            }
            .labelsHidden()
            .accessibilityLabel("Limit")
            .accessibilityValue(offer.current.name)
            // each level's name under its tick
            GeometryReader { g in
                // as wide as the space between stops allows, so five names don't run into each other
                let room = min(78, (g.size.width - 2 * Self.inset) / n - 4)
                ForEach(Array(offer.levels.enumerated()), id: \.element) { i, l in
                    Text(l.name).font(.caption2).foregroundStyle(Ink.muted)
                        .multilineTextAlignment(.center).frame(width: room)
                        .position(x: Self.inset + (g.size.width - 2 * Self.inset) * CGFloat(i) / n, y: 14)
                }
            }
            .frame(height: 30)
            .accessibilityHidden(true)
            if words { advice }
        }
    }

    /// The recommendation as text, with what it does; once it's at the recommended level, what that level does.
    var advice: some View {
        let limited = offer.current != .full && offer.current != .cooler
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
}
