import AppKit
import CoolHeadCore
import SwiftUI
import UniformTypeIdentifiers

/// The past week, from macOS's own power log: what used the most energy, what woke the chip most often, and why the Mac
/// woke from sleep. Read when shown (off the main thread), never on the refresh loop; nothing is kept but the totals.
/// Every sentence comes from PowerHistory, so `coolhead history` prints the same words.
struct HistoryView: View {
    /// Made-up history for screenshots; nil reads this Mac's power log.
    var sample: PowerHistory? = nil
    /// Closes the view, back to the cards.
    var close: (() -> Void)? = nil
    @State private var history: PowerHistory?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let h = sample ?? history {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(h.title).font(.body.weight(.semibold))
                        Spacer()
                        if let close { Button("Done", action: close).buttonStyle(.link).font(.callout) }
                    }
                    Text(PowerHistory.source).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                let energy = h.topEnergy()
                if !energy.isEmpty {
                    Section(heading: PowerHistory.energyHeading, note: PowerHistory.energyNote) {
                        ForEach(Array(zip(energy, PowerHistory.names(energy.map(\.0))).enumerated()), id: \.offset) { _, row in
                            Row(user: row.0.0, name: row.1.name, what: row.1.what, figure: PowerHistory.share(row.0.1),
                                fraction: row.0.1, sample: sample != nil)          // a share, so the bar is out of 100%
                        }
                    }
                }
                let wakeups = h.topWakeups()
                if !wakeups.isEmpty {
                    Section(heading: PowerHistory.wakeupsHeading, note: PowerHistory.wakeupsNote) {
                        ForEach(Array(zip(wakeups, PowerHistory.names(wakeups.map(\.0))).enumerated()), id: \.offset) { _, row in
                            Row(user: row.0.0, name: row.1.name, what: row.1.what, figure: PowerHistory.perHour(row.0.1),
                                fraction: row.0.1 / (wakeups.first?.1 ?? 1), sample: sample != nil)
                        }
                    }
                }
                Section(heading: PowerHistory.wakesHeading, note: nil) {
                    Text(h.wakesSummary).font(.callout).foregroundStyle(Ink.text)
                    ForEach(h.wakesByCause, id: \.0) { cause, wakes in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("·").foregroundStyle(Ink.muted)
                            Text(PowerHistory.sentence(cause, wakes)).font(.callout).foregroundStyle(Ink.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

    /// A heading, its rows on a card, and a line saying what the figures mean.
    struct Section<Content: View>: View {
        let heading: String
        let note: String?
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(heading).font(.callout.weight(.semibold))
                VStack(alignment: .leading, spacing: 9) { content }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
                if let note { Text(note).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    /// An app or program: its icon, its name (and what it is, if not an app), the figure, and a bar: out of the whole
    /// for a share, against the first row for a rate.
    struct Row: View {
        let user: PowerHistory.User
        let name: String
        let what: String?
        let figure: String
        let fraction: Double
        let sample: Bool

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                icon.frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name).font(.callout).foregroundStyle(Ink.text).lineLimit(1)
                        if let what { Text(what).font(.caption).foregroundStyle(Ink.muted).lineLimit(1) }
                        Spacer(minLength: 8)
                        Text(figure).font(.callout.monospacedDigit()).foregroundStyle(Ink.text)
                    }
                    GeometryReader { g in
                        Capsule().fill(Color.accentColor.opacity(0.55))
                            .frame(width: max(3, g.size.width * min(1, fraction)), height: 4)
                    }
                    .frame(height: 4)
                }
            }
            .accessibilityElement(children: .combine)
        }

        /// The app's own icon if it is installed (not in screenshots, which show no one's own apps), else macOS's plain
        /// app icon; the Apple logo for parts of macOS, a gear for background programs.
        @ViewBuilder var icon: some View {
            if user.name.what == .app {
                let url = sample ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: user.id)
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
                    .resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: user.name.what == .macOS ? "apple.logo" : "gearshape").font(.system(size: 14)).foregroundStyle(Ink.muted)
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
            ("history", AnyView(HistoryView(sample: .sample()) {}.padding(16).frame(width: 412).background(.background))),
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
