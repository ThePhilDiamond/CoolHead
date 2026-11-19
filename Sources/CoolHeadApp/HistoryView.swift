import AppKit
import CoolHeadCore
import SwiftUI
import UniformTypeIdentifiers

/// The past week, from macOS's own power log: what used the most energy, and why the Mac woke from sleep. Read when shown (off the main thread), never on the refresh loop; nothing is kept but the totals.
/// Every sentence comes from PowerHistory, so `coolhead history` prints the same words.
struct HistoryView: View {
    /// Made-up history for screenshots; nil reads this Mac's power log.
    var sample: PowerHistory? = nil
    /// Closes the view, back to the cards.
    var close: (() -> Void)? = nil
    @State private var history: PowerHistory?
    @State private var loaded = false
    /// One section open at a time, the energy first; the other folds to its heading (Phil, 18 November 2026: "The trends
    /// page if we limit to one section showing at a time and the rest stay collapsed, it could control vertical space").
    @State private var openSection: String? = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_WAKES"] != nil ? "wakes" : "energy"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let h = sample ?? history {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(h.title).font(.body.weight(.semibold))
                        Spacer()
                        // the same close as every other tool (Phil, 19 November 2026: "The Trends tool also has a "Done"
                        // close option in the top right, while others have an "X"")
                        if let close {
                            Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                                .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
                        }
                    }
                    Text(PowerHistory.source).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                let energy = h.energyRows()
                if !energy.isEmpty {
                    Section(heading: PowerHistory.energyHeading, note: PowerHistory.energyNote, open: openSection == "energy",
                            toggle: { fold("energy") }) {
                        ForEach(Array(energy.enumerated()), id: \.offset) { _, row in
                            // a share, so the bar is out of 100%; what it means shows under it, with no click (Phil, 19
                            // November 2026, of the wake rows' explanations: "It seems like a needless extra click
                            // anyway", then of these: "Yes, same for energy")
                            Row(row: row, sample: sample != nil)
                        }
                    }
                }
                Section(heading: PowerHistory.wakesHeading, note: nil, open: openSection == "wakes", toggle: { fold("wakes") }) {
                    Text(h.wakesSummary).font(.callout).foregroundStyle(Ink.text)
                    // every wake as one thin bar, split by cause, so each reads as a share of the whole (Phil, 19 November
                    // 2026: "maybe as a pie chart or something that illustrates "share of total" rather than arbitrary
                    // bars?"); a bar, not a pie, so the rows' figures sit beside it and a small cause still shows
                    if !h.wakes.isEmpty { WakeSplit(causes: h.wakesByCause, total: h.wakes.count).padding(.bottom, 2) }
                    // then one row per cause: its color, a symbol, a short name, the count and its share, and what it
                    // means under it, always shown (Phil, 19 November 2026: "Can we also fix the "Why it woke from sleep"
                    // section to be more visual? it's a wall of text now", then "Remove the chevrons and include the text
                    // persistently visible when that section is expanded. It seems like a needless extra click anyway")
                    ForEach(h.wakesByCause, id: \.0) { cause, wakes in
                        WakeRow(cause: cause, wakes: wakes, total: h.wakes.count)
                    }
                }
            } else {
                Text(loaded ? "No history to show: this Mac's power log couldn't be read." : "Reading macOS's power log…")
                    .font(.callout).foregroundStyle(Ink.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard sample == nil, !loaded else { return }
            history = await Task.detached(priority: .utility) { PowerHistory.read() }.value
            loaded = true
        }
    }

    func fold(_ section: String) { withAnimation(.easeOut(duration: 0.15)) { openSection = openSection == section ? nil : section } }

    /// A heading that folds and opens it, its rows on a card, and a line saying what the figures mean.
    struct Section<Content: View>: View {
        let heading: String
        let note: String?
        let open: Bool
        let toggle: () -> Void
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(heading).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "shown" : "hidden")
                if open {
                    VStack(alignment: .leading, spacing: 9) { content }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
                    if let note { Text(note).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
                }
            }
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

    /// Every wake as one thin bar, 8 points tall with round ends, a part per cause in the rows' order, 2 points apart.
    /// Each cause keeps its own color whatever its rank, from a palette checked for color blindness in light and dark
    /// (the dataviz skill's validator: every check passes; in light, three colors are under 3:1 against the card, so
    /// the rows beside the bar carry every name and figure).
    struct WakeSplit: View {
        let causes: [(PowerHistory.Cause, [PowerHistory.Wake])]
        let total: Int
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            GeometryReader { g in
                let gaps = CGFloat(max(0, causes.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(causes, id: \.0) { cause, wakes in
                        Rectangle().fill(WakeSplit.color(cause, scheme))
                            .frame(width: max(2, (g.size.width - gaps) * CGFloat(wakes.count) / CGFloat(max(1, total))))
                            .help("\(PowerHistory.label(cause)): \(wakes.count), \(PowerHistory.share(Double(wakes.count) / Double(max(1, total))))")
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel(causes.map { "\(PowerHistory.label($0.0)), \(PowerHistory.share(Double($0.1.count) / Double(max(1, total))))" }
                .joined(separator: "; "))
        }

        /// A cause's color, fixed to the cause, never to its rank: the dataviz skill's eight categorical hues, stepped for
        /// light and dark, and grey for reasons Cool Head doesn't recognize.
        static func color(_ cause: PowerHistory.Cause, _ scheme: ColorScheme = .light) -> Color {
            let light: [PowerHistory.Cause: UInt32] = [.schedule: 0x2a78d6, .lid: 0xeb6834, .wireless: 0x1baf7a, .plug: 0xeda100,
                                                         .input: 0xe87ba4, .network: 0x008300, .bluetooth: 0x6250d6, .button: 0xe34948]
            let dark: [PowerHistory.Cause: UInt32] = [.schedule: 0x3987e5, .lid: 0xd95926, .wireless: 0x199e70, .plug: 0xc98500,
                                                        .input: 0xd55181, .network: 0x0ca30c, .bluetooth: 0x9085e9, .button: 0xe66767]
            guard let hex = (scheme == .dark ? dark : light)[cause] else { return Color.gray }
            return Color(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
        }
    }

    /// One reason the Mac woke: its color, symbol, short name, how many times, and its share, with what it means under it.
    struct WakeRow: View {
        let cause: PowerHistory.Cause
        let wakes: [PowerHistory.Wake]
        let total: Int
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 8) {
                    // its color in the bar above, so the row is the bar's legend
                    RoundedRectangle(cornerRadius: 2).fill(WakeSplit.color(cause, scheme)).frame(width: 8, height: 8)
                    Image(systemName: WakeRow.symbol(cause)).font(.system(size: 14)).foregroundStyle(Ink.muted)
                        .frame(width: 22, height: 22)
                    Text(PowerHistory.label(cause)).font(.callout).foregroundStyle(Ink.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(wakes.count)").font(.callout.monospacedDigit()).foregroundStyle(Ink.text)
                    Text(PowerHistory.share(Double(wakes.count) / Double(max(1, total)))).font(.callout.monospacedDigit())
                        .foregroundStyle(Ink.muted).frame(minWidth: 62, alignment: .trailing)
                }
                Text(PowerHistory.detail(cause, wakes)).font(.caption).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 46)
            }
            .accessibilityElement(children: .combine)
        }

        static func symbol(_ cause: PowerHistory.Cause) -> String {
            switch cause {
            case .lid: return "laptopcomputer"
            case .button: return "power"
            case .input: return "keyboard"
            case .plug: return "powerplug"
            case .network: return "network"
            case .bluetooth: return "dot.radiowaves.left.and.right"
            case .wireless: return "wifi"
            case .schedule: return "timer"
            case .other: return "questionmark.circle"
            }
        }
    }

    /// Made-up history when taking screenshots (COOLHEAD_SNAPSHOT_HISTORY), so no one's own apps appear; nil otherwise.
    static let snapshotSample: PowerHistory? = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_HISTORY"] != nil ? .sample() : nil

    /// For screenshots: COOLHEAD_SNAPSHOT_HISTORY draws, in light and dark, the panel open on the history (as it
    /// scrolls) to <prefix>-history-panel-light.png and -dark.png, and the whole history to <prefix>-history-light.png
    /// and -dark.png, all with made-up history. It runs before watching starts, so it shows and changes nothing of the Mac's.
    @MainActor static func snapshot(to prefix: String) {
        Watcher.shared.showHistory = true
        let views: [(String, AnyView)] = [
            ("history-panel", AnyView(PanelView(watcher: Watcher.shared).background(.background))),
            ("history", AnyView(HistoryView(sample: .sample()) {}.padding(16).frame(width: PanelView.width).background(.background))),
        ]
        for (file, view) in views { for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: look)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: look)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(file)-\(name).png"))
        } }
    }
}
