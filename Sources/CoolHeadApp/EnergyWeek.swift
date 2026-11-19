import AppKit
import CoolHeadCore
import SwiftUI

/// The past week's energy use, from macOS's own power log, on the Battery page, folded to one line until opened (Phil,
/// 19 November 2026: "The energy usage can move into the power/battery tool", then, of the Trends tool and its wake
/// history, "Yes, drop Trends"). Read when first opened, off the main thread, never on the refresh loop; nothing is
/// kept but the totals. Every sentence comes from PowerHistory, so `coolhead history` prints the same words, and the
/// wake history is still there for anyone who wants it.
struct EnergyWeek: View {
    /// Made-up history for screenshots; nil reads this Mac's power log.
    var sample: PowerHistory? = nil
    @State private var open = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ENERGY"] != nil
    @State private var history: PowerHistory?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").foregroundStyle(Ink.muted)
                    Text("What used the most energy this week").foregroundStyle(Ink.text)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "shown" : "hidden")
            if open {
                if let h = sample ?? history, !h.energyRows().isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(h.energyRows().enumerated()), id: \.offset) { _, row in Row(row: row, sample: sample != nil) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
                    Text(PowerHistory.energyNote + " " + PowerHistory.source)
                        .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(loaded || sample != nil ? "No energy history to show: this Mac's power log couldn't be read." : "Reading macOS's power log…")
                        .font(.caption).foregroundStyle(Ink.muted)
                }
            }
        }
        .task(id: open) {
            guard open, sample == nil, !loaded else { return }
            history = await Task.detached(priority: .utility) { PowerHistory.read() }.value
            loaded = true
        }
    }

    /// An app or program, or macOS itself: its icon, its name (and what it is, if not an app), its share and a bar out
    /// of the whole, with what the share means and whether to do anything under it (Phil, 17 November 2026: "clicking an
    /// item in the trends tool tells the user more about it"; shown without a click since 19 November 2026).
    struct Row: View {
        let row: PowerHistory.EnergyRow
        let sample: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    icon.frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.name).font(.callout).foregroundStyle(Ink.text).lineLimit(1)
                            if let what = row.what { Text(what).font(.caption).foregroundStyle(Ink.muted).lineLimit(1) }
                            Spacer(minLength: 8)
                            Text(PowerHistory.share(row.share)).font(.callout.monospacedDigit()).foregroundStyle(Ink.text)
                        }
                        GeometryReader { g in
                            Capsule().fill(Color.accentColor.opacity(0.55))
                                .frame(width: max(3, g.size.width * min(1, row.share)), height: 4)
                        }
                        .frame(height: 4)
                    }
                }
                Text(row.detail).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
            }
            .accessibilityElement(children: .combine)
        }

        /// The app's own icon if it is installed (not in screenshots, which show no one's own apps), else macOS's plain
        /// app icon; the Apple logo for macOS itself, a gear for background programs.
        @ViewBuilder var icon: some View {
            if let user = row.user, user.name.what == .app {
                let url = sample ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: user.id)
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
                    .resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: row.user == nil ? "apple.logo" : "gearshape").font(.system(size: 14)).foregroundStyle(Ink.muted)
            }
        }
    }

}
