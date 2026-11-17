import AppKit
import CoolHeadCore
import SwiftUI
import UniformTypeIdentifiers

/// Along the bottom of the panel: the tools, each an icon with its name (the names can be hidden from the right-click
/// menu), and each opening in the panel's middle (Phil, 16 November 2026: "Tools go here, settings go in the right-click
/// menu."). Opening one closes any other.
struct ToolsBar: View {
    let watcher: Watcher
    @ObservedObject var network = NetworkTester.shared
    @ObservedObject var tools = Tools.shared
    @AppStorage(Tools.labelsKey) private var labels = true
    /// A battery to show: this Mac's, or in a screenshot a made-up one.
    var hasBattery: Bool {
        watcher.mac.batteryPercent != nil || HardwareWatch.shared.report?.battery != nil || PanelView.sampleSnapshot
    }
    /// Trends (the power log's charts) appears when that tool is in the app: whether it's open, and how to toggle it.
    var trends: (shown: Bool, toggle: () -> Void)? = nil

    var body: some View {
        HStack(spacing: labels ? 2 : 6) {
            ToolButton(symbol: "network", name: "Network", tip: "Test my network", labels: labels, on: network.shown) {
                let open = !network.shown
                closeAll()
                if open { network.open() }
            }
            // the battery's own page, beside Network, the other check (Phil, 16 November 2026: "the battery tool should be
            // next to the network tool"); a Mac with no battery has no Battery tool
            if hasBattery {
                ToolButton(symbol: "battery.75percent", name: "Battery", tip: "Battery health and Battery Saver", labels: labels, on: tools.battery) {
                    let open = !tools.battery
                    closeAll()
                    tools.battery = open
                }
            }
            // the hardware checks on one page, after Battery, the other part of the Mac itself (Phil, 16 November 2026:
            // "Yes build the hardware tool page")
            ToolButton(symbol: "stethoscope", name: "Hardware", tip: "Hardware checks", labels: labels, on: tools.hardware) {
                let open = !tools.hardware
                closeAll()
                tools.hardware = open
            }
            if let trends {
                // a chart, not a clock: it's for spotting patterns, not looking back (Phil, 16 November 2026)
                ToolButton(symbol: "chart.xyaxis.line", name: "Trends", tip: "Trends this week", labels: labels, on: trends.shown) {
                    let open = !trends.shown
                    closeAll()
                    if open { trends.toggle() }
                }
            }
            ToolButton(symbol: "checkmark.shield", name: "Trusted", tip: "Trusted apps and jobs", labels: labels, on: tools.trusted) {
                let open = !tools.trusted
                closeAll()
                tools.trusted = open
            }
            // no Activity Monitor button: it's not Cool Head's tool, and anyone who wants it knows where it is (Phil,
            // 16 November 2026: "It's not our tool so we should drop it."); no Quit either: it's in the right-click menu
            // (Phil, 16 November 2026: "Since we added quit to the right-click menu, can drop the quit button.")
            Spacer(minLength: 4)
            // Report on its own at the right: it's about Cool Head, not the Mac
            ToolButton(symbol: "exclamationmark.bubble", name: "Report", tip: "Report a problem", labels: labels, on: watcher.showReport) {
                let open = !watcher.showReport
                closeAll()
                watcher.showReport = open
            }
        }
    }

    func closeAll() { Tools.closeAll(watcher) }
}

/// Which of the panel's own tools is open (Report a problem's flag lives in the watcher, as before), and the setting
/// for the tools' names.
@MainActor
final class Tools: ObservableObject {
    static let shared = Tools()
    @Published var trusted = false
    @Published var battery = false
    @Published var hardware = false

    /// Closes every tool, in one place, so they all behave alike: opening one closes the others, and the panel always
    /// opens with none open (Phil, 16 November 2026: "We need consistency across the tools, and I think the panel should
    /// always open with no tools selected"). A network test still running is stopped.
    static func closeAll(_ watcher: Watcher) {
        NetworkTester.shared.close()
        shared.trusted = false
        shared.battery = false
        shared.hardware = false
        watcher.showReport = false
        watcher.showHistory = false
    }
    /// Show each tool's name under its icon (on by default; Hide Tool Names in the right-click menu turns it off).
    nonisolated static let labelsKey = "toolLabels"
    static var labels: Bool {
        get { UserDefaults.standard.object(forKey: labelsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: labelsKey) }
    }
}

/// A tool: its icon, with its name under it (or, with names hidden, as a tooltip), tinted while it's open.
struct ToolButton: View {
    let symbol: String
    let name: String
    let tip: String
    let labels: Bool
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15)).frame(height: 18)
                if labels { Text(name).font(.caption2) }
            }
            .frame(minWidth: labels ? 52 : 30)
            .padding(.vertical, labels ? 5 : 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.16) : hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Color.accentColor : hovering ? Ink.text : Ink.muted)
        .onHover { hovering = $0 }
        .help(tip)
        .accessibilityLabel(tip)
    }
}

/// The apps and jobs you trust, as a standard macOS list: select one and press − to stop trusting it, or + to choose an
/// app to trust. Jobs and scripts are trusted from the clock on their card, where Cool Head knows exactly which one.
struct TrustedView: View {
    let watcher: Watcher
    @ObservedObject var tools = Tools.shared
    @State private var list: [Item]
    @State private var selected: String?
    @State private var note: String?

    struct Item: Identifiable, Equatable {
        let key: String
        let name: String
        var id: String { key }
        /// What it is, from how it was trusted: an app (by its identifier), a script, or a program.
        var kind: String { key.hasPrefix("app:") ? "App" : key.hasPrefix("script:") ? "Script" : "Program" }
    }

    /// `preset` is for renders; the panel reads the list.
    init(watcher: Watcher, preset: [Item]? = nil) {
        self.watcher = watcher
        _list = State(initialValue: preset ?? TrustedView.load())
    }

    static func load() -> [Item] {
        Trust.all.map { Item(key: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Trusted", systemImage: "checkmark.shield").font(.body.weight(.semibold))
                Spacer()
                Button { tools.trusted = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            Text("Their cards stay calm. We still flag one if it looks stuck, your Mac gets hot, or it runs nonstop for \(Int(Trust.limitHours)) hours.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            // the list and its +/− bar, in one bordered box, as in System Settings
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if list.isEmpty {
                        Text("No trusted apps or jobs")
                            .font(.callout).foregroundStyle(Ink.muted)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                            row(item, stripe: i % 2 == 1)
                        }
                    }
                }
                .frame(minHeight: 64, alignment: .top)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
                HStack(spacing: 0) {
                    barButton("plus", "Trust an app") { choose() }
                    Divider().frame(height: 16)
                    barButton("minus", "Stop trusting the selected one") {
                        guard let key = selected else { return }
                        watcher.untrust(key: key)
                        list = TrustedView.load()
                        selected = nil
                        note = nil
                    }
                    .disabled(selected == nil)
                    Divider().frame(height: 16)
                    Spacer()
                }
                .frame(height: 22)
                .background(Color.primary.opacity(0.03))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.edge, lineWidth: 1))
            Text(note ?? "To trust a job or script, use the clock on its card.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    func row(_ item: Item, stripe: Bool) -> some View {
        let on = selected == item.key
        return HStack(spacing: 8) {
            icon(item).frame(width: 18, height: 18)
            Text(item.name).font(.callout).lineLimit(1)
            Spacer()
            Text(item.kind).font(.caption).foregroundStyle(on ? Color.white.opacity(0.85) : Ink.muted)
        }
        .foregroundStyle(on ? Color.white : Ink.text)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(on ? Color.accentColor : stripe ? Color.primary.opacity(0.035) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = on ? nil : item.key }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// An app's own icon, found by its identifier; a script or program gets a plain one.
    @ViewBuilder func icon(_ item: Item) -> some View {
        if item.key.hasPrefix("app:"), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: String(item.key.dropFirst(4))) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: item.key.hasPrefix("app:") ? "app" : item.key.hasPrefix("script:") ? "doc.text" : "terminal").foregroundStyle(Ink.muted)
        }
    }

    func barButton(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 26, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
        .accessibilityLabel(tip)
    }

    /// + : choose an app in Applications to trust.
    func choose() {
        let open = NSOpenPanel()
        open.title = "Trust an app"
        open.prompt = "Trust"
        open.allowedContentTypes = [.application]
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let url = open.url else { return }
        if watcher.trust(appPath: url.path) {
            list = TrustedView.load()
            selected = list.first { $0.name == (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension }?.key
            note = nil
        } else {
            note = "macOS's own apps can't be trusted: Cool Head explains them instead."
        }
    }
}
