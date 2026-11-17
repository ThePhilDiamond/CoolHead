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
                let energy = h.energyRows()
                if !energy.isEmpty {
                    Section(heading: PowerHistory.energyHeading, note: PowerHistory.energyNote) {
                        ForEach(Array(energy.enumerated()), id: \.offset) { _, row in
                            Row(row: row, sample: sample != nil)          // a share, so the bar is out of 100%
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

    /// An app or program, or macOS itself: its icon, its name (and what it is, if not an app), its share and a bar out
    /// of the whole. A click opens what the share means and whether to do anything (Phil, 17 November 2026: "clicking an
    /// item in the trends tool tells the user more about it").
    struct Row: View {
        let row: PowerHistory.EnergyRow
        let sample: Bool
        @State private var open = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_OPEN"] != nil

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
                            Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Ink.muted)
                        }
                        GeometryReader { g in
                            Capsule().fill(Color.accentColor.opacity(0.55))
                                .frame(width: max(3, g.size.width * min(1, row.share)), height: 4)
                        }
                        .frame(height: 4)
                    }
                }
                if open {
                    Text(row.detail).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 32)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
            .hoverHighlight(true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
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
