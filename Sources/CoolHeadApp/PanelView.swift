import AppKit
import CoolHeadCore
import SwiftUI

struct PanelView: View {
    let watcher: Watcher

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(status).font(.headline)
                Spacer()
                SettingsMenu(watcher: watcher)
            }
            if shownCards.isEmpty {
                Text(watcher.mac.cores == 0 ? "Taking a first look…" : "Nothing needs a look.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shownCards) { CardView(live: $0, watcher: watcher) }
            }
            Text(footer).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 360)
    }

    /// For screenshots: COOLHEAD_SNAPSHOT_ONLY shows only cards whose headline contains that phrase,
    /// so a screenshot never shows the person's own processes.
    var shownCards: [LiveCard] {
        guard let only = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] else { return watcher.cards }
        return watcher.cards.filter { $0.card.headline.contains(only) }
    }

    var status: String {
        let n = shownCards.filter(\.needsLook).count
        let heat: String
        switch watcher.mac.thermal {
        case "serious", "critical": heat = "Running hot"
        case "fair": heat = "Running warm"
        default: heat = n > 0 ? "Running cool" : "All calm"
        }
        if n > 0 { return "\(heat): \(n) to look at" }
        let jobs = shownCards.filter { $0.card.state == .working || $0.card.state == .starting }.count
        return jobs == 0 ? heat : "\(heat) · \(jobs == 1 ? "1 job" : "\(jobs) jobs") running"
    }

    var footer: String {
        var parts: [String] = []
        if let h = watcher.mac.healthPercent, let c = watcher.mac.cycles {
            parts.append("Battery holds \(h)% of its original charge (\(c) cycles)")
        }
        parts.append(String(format: "Cool Head uses %.1f%%", watcher.overhead * 100))
        return parts.joined(separator: " · ")
    }
}

struct CardView: View {
    let live: LiveCard
    let watcher: Watcher
    @State private var open = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_OPEN"] != nil  // screenshots show it open
    @State private var facts = false
    @State private var confirmStop: Fix?
    @State private var cooled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(live.card.headline)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if !live.card.fixes.isEmpty {
                Button(open ? "Hide fixes" : "Explore fixes") { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
                    .buttonStyle(.borderedProminent)
                    .tint(live.needsLook ? .orange : .accentColor)
                    .controlSize(.small)
            }
            if open {
                Text(live.card.explanation)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(live.card.fixes) { FixRow(fix: $0, cooled: cooled) { act($0) } }
                }
                DisclosureGroup("The facts", isExpanded: $facts) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(live.details, id: \.self) { Text($0) }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog("Stop it?", isPresented: Binding(get: { confirmStop != nil }, set: { if !$0 { confirmStop = nil } })) {
            Button("Stop it", role: .destructive) { if let p = live.pid { kill(p, SIGTERM) }; confirmStop = nil }
            Button("Cancel", role: .cancel) { confirmStop = nil }
        } message: {
            Text(confirmStop?.consequence ?? "")
        }
    }

    func act(_ fix: Fix) {
        switch fix.kind {
        case .wait(let until):
            watcher.snooze(live, until: until)
        case .stop:
            confirmStop = fix
        case .lookUp(let name):
            // only the process name is searched for: no paths, nothing about this Mac
            var u = URLComponents(string: "https://duckduckgo.com/")!
            u.queryItems = [URLQueryItem(name: "q", value: "macOS \(name) high CPU")]
            if let url = u.url { NSWorkspace.shared.open(url) }
        case .cooler:
            guard let p = live.pid else { return }
            // background priority: macOS moves it to the efficiency cores and throttles its disk use
            setpriority(4 /* PRIO_DARWIN_PROCESS */, id_t(p), cooled ? 0 : 0x1000 /* PRIO_DARWIN_BG */)
            cooled.toggle()
        case .quitApp(let name):
            NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.terminate()
        case .info:
            break
        }
    }
}

/// One option: a button with what it would cause underneath. The recommended one stands out.
struct FixRow: View {
    let fix: Fix
    let cooled: Bool
    let run: (Fix) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if fix.kind == .info {
                Text(fix.title).font(.callout.weight(.medium))
            } else {
                Button { run(fix) } label: {
                    Text(fix.kind == .cooler && cooled ? "Back to full speed" : fix.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(fix.recommended ? Color.accentColor : .clear, lineWidth: 1.5))
                .controlSize(.regular)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if fix.recommended { Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                if !fix.consequence.isEmpty {
                    Text(fix.consequence).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SettingsMenu: View {
    let watcher: Watcher
    @State private var login = LoginItem.on
    @State private var notify = Alerts.enabled

    var body: some View {
        Menu {
            Toggle("Open at login", isOn: $login).onChange(of: login) { _, v in LoginItem.set(v) }
            Toggle("Notifications", isOn: $notify).onChange(of: notify) { _, v in Alerts.enabled = v }
            Divider()
            Button("Open Activity Monitor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Button("About Cool Head") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            Button("Quit Cool Head") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
