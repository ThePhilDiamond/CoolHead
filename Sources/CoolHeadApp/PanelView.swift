import AppKit
import CoolHeadCore
import SwiftUI

struct PanelView: View {
    let watcher: Watcher

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: Badge.symbol(watcher.level))
                    .foregroundStyle(Color(nsColor: Badge.color(watcher.level)))
                    .accessibilityLabel(watcher.level == .good ? "All well" : watcher.level == .warning ? "Needs a look" : "Problem")
                Text(status).font(.headline)
                Spacer()
                Text("Cool Head v\(CoolHead.version)").font(.caption2).foregroundStyle(Ink.muted)
            }
            if shownCards.isEmpty {
                Text(watcher.mac.cores == 0 ? "Taking a first look…" : "Nothing needs a look.")
                    .foregroundStyle(Ink.muted)
            } else {
                ForEach(shownCards) { CardView(live: $0, watcher: watcher) }
            }
            Divider()
            if !footer.isEmpty { Text(footer).font(.caption).foregroundStyle(Ink.muted) }
            BottomBar()
        }
        .padding(16)
        .frame(width: 380)
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
        let stuck = shownCards.filter { $0.card.state == .stalled }.count
        if stuck > 0 { return "\(heat): \(stuck) looks stuck" + (n > stuck ? ", \(n - stuck) to look at" : "") }
        if n > 0 { return "\(heat): \(n) to look at" }
        let jobs = shownCards.filter { $0.card.state == .working || $0.card.state == .starting }.count
        return jobs == 0 ? heat : "\(heat) · \(jobs == 1 ? "1 job" : "\(jobs) jobs") running"
    }

    var footer: String {
        var parts: [String] = []
        if let h = watcher.mac.healthPercent, let c = watcher.mac.cycles {
            parts.append("Battery holds \(h)% of its original charge (\(c) cycles)")
        }
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
    @State private var sharing = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_SHARE"] != nil  // screenshots

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
                    .font(.callout).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(live.card.fixes) { FixRow(fix: $0, cooled: cooled) { act($0) } }
                }
                if sharing, let r = live.report { ShareView(title: r.title, report: r.body) { sharing = false } }
                DisclosureGroup("The facts", isExpanded: $facts) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(live.details, id: \.self) { Text($0) }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Ink.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
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
        case .share:
            withAnimation(.easeOut(duration: 0.15)) { sharing.toggle() }
        case .info:
            break
        }
    }
}

/// Exactly what would be shared, before anything happens. Opening it in GitHub is the person's choice, and they
/// can still edit or abandon the issue there; Cool Head sends nothing itself.
struct ShareView: View {
    let title: String
    let report: String
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This is everything that would be shared. Read it first.")
                .font(.caption.weight(.semibold))
            ScrollView {
                Text(report.replacingOccurrences(of: "**", with: ""))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Button("Open in GitHub") {
                    if let u = CaseReport.issueURL(title: title, report: report) { NSWorkspace.shared.open(u) }
                    done()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(title)\n\n\(report)", forType: .string)
                    copied = true
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button("Cancel", action: done).buttonStyle(.plain).font(.caption).foregroundStyle(Ink.muted)
            }
            Text("GitHub opens in your browser with this filled in. You can edit it there, and nothing is posted until you press Submit.")
                .font(.caption2).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                if fix.recommended { Text("Recommended").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                if !fix.consequence.isEmpty {
                    Text(fix.consequence).font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Along the bottom: the two settings as switches, then Activity Monitor, About and Quit as line icons.
struct BottomBar: View {
    @State private var login = LoginItem.on
    @State private var notify = Alerts.enabled

    var body: some View {
        HStack(spacing: 10) {
            SmallSwitch(label: "Notifications", isOn: $notify).onChange(of: notify) { _, v in Alerts.enabled = v }
            SmallSwitch(label: "Open at login", isOn: $login).onChange(of: login) { _, v in LoginItem.set(v); login = LoginItem.on }
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                IconButton(symbol: "waveform.path.ecg", tip: "Launch Activity Monitor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                IconButton(symbol: "info.circle", tip: "About Cool Head") { About.show() }
                IconButton(symbol: "power", tip: "Quit") { NSApp.terminate(nil) }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.caption)
    }
}

/// A switch smaller than macOS's smallest ("mini"), with its label at normal size. Clicking the label toggles it too.
struct SmallSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(label).fixedSize().onTapGesture { isOn.toggle() }
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .scaleEffect(0.78)
                .frame(width: 30, height: 14)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A line-icon button with its tooltip centred above it on hover (the system tooltip appears at the pointer instead).
struct IconButton: View {
    let symbol: String
    let tip: String
    let action: () -> Void
    @State private var hovering = false

    init(symbol: String, tip: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.tip = tip; self.action = action
        // screenshots: COOLHEAD_SNAPSHOT_HOVER names a tooltip to show
        _hovering = State(initialValue: ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_HOVER"] == tip)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? Ink.text : Ink.muted)
        .onHover { hovering = $0 }
        .overlay(alignment: .top) {
            if hovering {
                Text(tip)
                    .font(.caption)
                    .foregroundStyle(Ink.text)
                    .fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Ink.edge, lineWidth: 1))
                    .offset(y: -26)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(tip)
    }
}

/// Text and surface colours chosen for contrast in both light and dark, instead of macOS's paler secondary greys.
enum Ink {
    /// Main text.
    static let text = Color.primary
    /// Supporting text: still well above 7:1 contrast on the card in light and dark.
    static let muted = Color.primary.opacity(0.82)
    /// A card: a slightly raised surface with a visible edge.
    static let card = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.19, alpha: 1) : NSColor(white: 0.965, alpha: 1)
    })
    static let edge = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.08)
    })
}
