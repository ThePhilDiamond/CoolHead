import CoolHeadCore
import SwiftUI

/// The CPU limit's control: macOS's own slider (CPUCap.Slider), stopping only at the levels (CPUCap.Level), slowest on the left with a
/// tortoise and Full speed on the right with a hare; Cooler, just before it, is Run it cooler with no limit. A move takes effect at once, so where it is now and what's chosen
/// are one thing: its name under the track is highlighted in Cool Head blue, as the track fills, with a point up to the thumb (25 November
/// 2026: in place of a tag over the thumb, which took a row of its own), and it moves when the slider is let go, since
/// only where it's let go applies; the recommendation is text under it, never marked on the slider.
/// Chosen over bars, a dial, segments, and buttons after six rounds of renders (notes/cpu-cap.md).
struct LimitGauge: View {
    let offer: CPUCap.Offer
    /// Whether to say the recommendation and what it does under the slider (on a card; the Managed by Cool Head line
    /// has its own words).
    var words = true
    /// On the frost (a Managed line): each stop's name in full-strength ink, not muted, so it reads over the ice.
    var onIce = false
    let pick: (CPUCap.Level) -> Void

    /// How far in from each side the slider's first and last stops sit, past the tortoise and the hare.
    static let inset: CGFloat = 51

    var body: some View {
        let current = offer.levels.firstIndex(of: offer.current) ?? 0
        let n = CGFloat(max(offer.levels.count - 1, 1)), at = CGFloat(current)
        VStack(alignment: .leading, spacing: 4) {
            // the tortoise and the hare as wide as puts each stop over its name: the thumb's middle at the first stop
            // is half a thumb (10 points) in from the slider's edge
            HStack(spacing: 8) {
                Image(systemName: "tortoise.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Ink.text)
                    .frame(width: Self.inset - 18).accessibilityHidden(true)
                LevelSlider(count: offer.levels.count, stop: current, name: offer.levels[current].name) { stop in
                    pick(offer.levels[stop])
                }
                Image(systemName: "hare.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Ink.text)
                    .frame(width: Self.inset - 18).accessibilityHidden(true)
            }
            // each level's name under its tick; where it is now highlighted, hugging its words
            GeometryReader { g in
                // as wide as the space between stops allows, so five names don't run into each other
                let room = min(78, (g.size.width - 2 * Self.inset) / n - 4)
                ForEach(Array(offer.levels.enumerated()), id: \.element) { i, l in
                    let here = i == Int(at)
                    Text(l.name).font(.caption2.weight(here ? .semibold : .regular))
                        .foregroundStyle(here ? Ink.onAccent : onIce ? Ink.text : Ink.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: room - 4)
                        .padding(.horizontal, 5).padding(.vertical, 2.5)
                        .background { if here { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.accent) } }
                        // a small point up to the thumb, tying the name to it
                        .overlay(alignment: .top) {
                            if here { Image(systemName: "arrowtriangle.up.fill").font(.system(size: 10)).foregroundStyle(Ink.accent).offset(y: -7) }
                        }
                        // every name from the same top, so the point always sits the same way under the thumb
                        .padding(.top, 5).frame(height: 40, alignment: .top)
                        .position(x: Self.inset + (g.size.width - 2 * Self.inset) * CGFloat(i) / n, y: 20)
                }
            }
            .frame(height: 40)
            .accessibilityHidden(true)
            if words { advice }
        }
    }

    /// The recommendation as text, with what it does; once it's at the recommended level, what that level does.
    var advice: some View {
        Group {
            if offer.suggested != offer.current {
                (Text("Recommended: \(offer.suggested.name), ").fontWeight(.semibold).foregroundColor(Ink.accent)
                 + Text(offer.suggested.effect(now: offer.now, app: offer.app)).foregroundColor(Ink.muted))
            } else {
                Text(offer.current.line(now: offer.now, app: offer.app)).foregroundColor(Ink.muted)
            }
        }
        .font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}

/// CPUCap.Slider in SwiftUI: it reports once, where it's let go, and only a change (CPUCap.Slider.toApply); the thumb
/// follows the level except while it's held, so a refresh mid-drag never pulls it back from under the pointer. A pick
/// that doesn't take leaves the level where it was, and the thumb goes back to it (CPUCap.Slider.settle).
struct LevelSlider: NSViewRepresentable {
    let count: Int
    let stop: Int
    /// What VoiceOver reads for where it is now: the level's name, not a number.
    let name: String
    let pick: (Int) -> Void

    final class Coordinator: NSObject {
        var pick: (Int) -> Void = { _ in }
        @objc func changed(_ s: CPUCap.Slider) {
            if let stop = s.toApply { pick(stop) }
            s.settle()
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> CPUCap.Slider {
        let s = CPUCap.Slider.make(levels: count, at: stop)
        s.target = context.coordinator
        s.action = #selector(Coordinator.changed(_:))
        s.setAccessibilityLabel("Limit")
        s.trackFillColor = Ink.accentNS
        return s
    }
    func updateNSView(_ s: CPUCap.Slider, context: Context) {
        context.coordinator.pick = pick
        s.show(stop)
        s.setAccessibilityValueDescription(name)
    }
}
