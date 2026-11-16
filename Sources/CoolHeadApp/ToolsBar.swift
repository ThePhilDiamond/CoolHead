import AppKit
import CoolHeadCore
import SwiftUI

/// Along the bottom of the panel: the tools, each an icon with its name, and each opening in the panel's middle (Phil,
/// 16 November 2026: "Tools go here, settings go in the right-click menu."). Opening one closes any other. Settings
/// (notifications, open at login, and the rest) are in the right-click menu.
struct ToolsBar: View {
    let watcher: Watcher
    @ObservedObject var network = NetworkTester.shared
    @ObservedObject var tools = Tools.shared
    /// The past week (power-log history) appears when that tool is in the app.
    var history: (shown: Bool, toggle: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ToolButton(symbol: "network", name: "Network", on: network.shown) {
                let open = !network.shown
                closeAll()
                if open { network.open() }
            }
            if let history {
                ToolButton(symbol: "clock.arrow.circlepath", name: "History", on: history.shown) {
                    let open = !history.shown
                    closeAll()
                    if open { history.toggle() }
                }
            }
            ToolButton(symbol: "checkmark.shield", name: "Trusted", on: tools.trusted) {
                let open = !tools.trusted
                closeAll()
                tools.trusted = open
            }
            ToolButton(symbol: "exclamationmark.bubble", name: "Report", on: watcher.showReport) {
                let open = !watcher.showReport
                closeAll()
                watcher.showReport = open
            }
            ToolButton(symbol: "waveform.path.ecg", name: "Activity", on: false) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Spacer(minLength: 4)
            ToolButton(symbol: "power", name: "Quit", on: false) { NSApp.terminate(nil) }
        }
    }

    func closeAll() {
        network.close()
        tools.trusted = false
        watcher.showReport = false
        if let history, history.shown { history.toggle() }
    }
}

/// Which of the panel's own tools is open (Report a problem's flag lives in the watcher, as before).
@MainActor
final class Tools: ObservableObject {
    static let shared = Tools()
    @Published var trusted = false
}

/// A tool: its icon above its name, tinted while it's open.
struct ToolButton: View {
    let symbol: String
    let name: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15)).frame(height: 18)
                Text(name).font(.caption2)
            }
            .frame(minWidth: 52)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.16) : hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Color.accentColor : hovering ? Ink.text : Ink.muted)
        .onHover { hovering = $0 }
        .accessibilityLabel(name)
    }
}

/// The apps and jobs you trust, each with Stop trusting. A trusted one stays listed but calm on its card.
struct TrustedView: View {
    @ObservedObject var tools = Tools.shared
    @State private var list: [(key: String, name: String)]
    /// `preset` is for renders; the panel reads the list.
    init(preset: [(key: String, name: String)]? = nil) { _list = State(initialValue: preset ?? TrustedView.load()) }

    static func load() -> [(key: String, name: String)] {
        Trust.all.map { (key: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Trusted", systemImage: "checkmark.shield").font(.body.weight(.semibold))
                Spacer()
                Button { tools.trusted = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            Text("These stay calm on their cards. We still flag one if it looks stuck, your Mac gets hot, or it runs nonstop for \(Int(Trust.limitHours)) hours.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            if list.isEmpty {
                Text("Nothing yet. Trust an app or job from the clock on its card.").font(.callout).foregroundStyle(Ink.muted)
            } else {
                ForEach(list, id: \.key) { item in
                    HStack {
                        Text(item.name).font(.callout)
                        Spacer()
                        Button("Stop trusting") { Trust.remove(item.key); list = TrustedView.load() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }
}
