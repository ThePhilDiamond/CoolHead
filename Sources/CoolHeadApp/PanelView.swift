import AppKit
import CoolHeadCore
import SwiftUI

struct PanelView: View {
    let watcher: Watcher
    @AppStorage("welcomed") private var welcomed = false

    /// The middle scrolls; the panel grows with it up to this height, so it stays easy to read.
    static var maxMiddle: CGFloat { min(560, (NSScreen.main?.visibleFrame.height ?? 900) * 0.62) }
    @State private var middleHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // fixed at the top
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: Badge.symbol(watcher.level))
                    .foregroundStyle(Color(nsColor: Badge.color(watcher.level)))
                    .accessibilityLabel(watcher.level == .good ? "All good" : watcher.level == .warning ? "Worth watching" : "Problem")
                Text(status).font(.headline)
                Spacer()
                VersionButton()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider()
            // scrolls once it is taller than the limit
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !welcomed { WelcomeCard { welcomed = true } }
                    UpdateBanner()
                    ForEach(watcher.cooledList) { PinnedRow(item: $0, watcher: watcher) }
                    if watcher.showReport {
                        ProblemView(watcher: watcher)
                    } else if shownCards.isEmpty {
                        Text(watcher.mac.cores == 0 ? "Taking a first look…" : "Nothing needs a look.")
                            .foregroundStyle(Ink.muted)
                    } else {
                        ForEach(shownCards) { CardView(live: $0, watcher: watcher) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { g in Color.clear.preference(key: MiddleHeight.self, value: g.size.height) })
            }
            .frame(height: min(max(middleHeight, 40), PanelView.maxMiddle))
            .onPreferenceChange(MiddleHeight.self) { middleHeight = $0 }
            Divider()
            // fixed at the bottom
            VStack(alignment: .leading, spacing: 10) {
                if !footer.isEmpty { Text(footer).font(.caption).foregroundStyle(Ink.muted) }
                BottomBar(watcher: watcher)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        }
        .frame(width: 412)
    }

    /// For screenshots: COOLHEAD_SNAPSHOT_ONLY shows only cards whose headline contains that phrase,
    /// so a screenshot never shows the person's own processes.
    var shownCards: [LiveCard] {
        guard let only = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] else { return watcher.cards }
        return watcher.cards.filter { $0.card.headline.contains(only) }
    }

    /// The heat word appears only when the Mac is warm or hot; otherwise the line is about what needs watching.
    var status: String {
        let n = shownCards.filter(\.needsLook).count
        let stuck = shownCards.filter { $0.card.state == .stalled }.count
        let jobs = shownCards.filter { $0.card.state == .working || $0.card.state == .starting }.count
        var watch: String?
        if stuck > 0 { watch = "\(stuck) looks stuck" + (n > stuck ? ", \(n - stuck) to watch" : "") }
        else if n > 0 { watch = "\(n) to watch" }
        let heat: String? = ["serious": "Running hot", "critical": "Running hot", "fair": "Running warm"][watcher.mac.thermal]
        switch (heat, watch) {
        case let (h?, w?): return "\(h) · \(w)"
        case let (nil, w?): return w.prefix(1).uppercased() + w.dropFirst()
        case let (h?, nil): return jobs > 0 ? "\(h) · \(jobs == 1 ? "1 job" : "\(jobs) jobs") running" : h
        default: return jobs > 0 ? "All calm · \(jobs == 1 ? "1 job" : "\(jobs) jobs") running" : "All calm"
        }
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
    @State private var note: String?          // what happened after a button, when it didn't simply work
    @State private var copiedFacts = false
    @State private var noteFailed = false      // the note reports a failure (orange, with a way to report it)
    @State private var sharing = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_SHARE"] != nil  // screenshots

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(live.card.headline)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if !live.card.fixes.isEmpty {
                // a warning offers fixes; a calm card only explains, with options if you want them anyway
                Button(open ? "Hide" : (live.needsLook ? "Explore fixes" : "Learn more")) {
                    withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(live.needsLook ? .orange : .accentColor)
                    .controlSize(.small)
            }
            if open {
                if !live.card.explanation.isEmpty {
                    Text(live.card.explanation)
                        .font(.callout).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    let coolerWasRecommended = live.card.fixes.contains { $0.kind == .cooler && $0.recommended }
                    ForEach(live.card.fixes) { f in
                        FixRow(fix: f, cooled: watcher.isCooled(live), run: { act($0) }, cooledCardRecommendedCooler: coolerWasRecommended)
                    }
                    if let n = note {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: noteFailed ? "exclamationmark.circle" : "checkmark.circle")
                            Text(n).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(noteFailed ? Color.orange : Color.green)
                        if noteFailed {
                            Button("Report a problem") { watcher.showReport = true }.buttonStyle(.link).font(.callout)
                        }
                    }
                }
                if sharing, let r = live.report { ShareView(title: r.title, report: r.body) { sharing = false } }
                // the whole line opens it, not just the arrow; the copy button at the end copies the details
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(facts ? 90 : 0))
                        Text("Nerdy stuff (detailed info)").font(.caption)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { facts.toggle() } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(facts ? "Hide the nerdy stuff" : "Show the nerdy stuff")
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(live.details.joined(separator: "\n"), forType: .string)
                        copiedFacts = true
                    } label: { Image(systemName: copiedFacts ? "checkmark" : "doc.on.doc").font(.caption) }
                    .buttonStyle(.plain)
                    .help(copiedFacts ? "Copied" : "Copy the details")
                    .accessibilityLabel("Copy the details")
                }
                .foregroundStyle(Ink.text)
                if facts {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(live.details, id: \.self) { Text($0) }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Ink.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
        .confirmationDialog(stopTitle, isPresented: Binding(get: { confirmStop != nil }, set: { if !$0 { confirmStop = nil } })) {
            Button("Stop it", role: .destructive) { show(watcher.stop(live)); confirmStop = nil }
            Button("Cancel", role: .cancel) { confirmStop = nil }
        } message: {
            Text(confirmStop?.consequence ?? "")
        }
    }

    /// Names the process, so the person knows exactly what they are stopping.
    var stopTitle: String {
        let s = live.displaySubject
        guard !s.isEmpty else { return "Stop this process?" }
        return "Stop " + (s.hasPrefix("Your ") ? "your " + s.dropFirst(5) : s) + "?"
    }

    func show(_ o: Watcher.Outcome) {
        switch o {
        case .done(let what): note = what; noteFailed = false
        case .gone: note = "It already finished, so nothing was done."; noteFailed = false
        case .failed(let why): note = "That didn't work: \(why)."; noteFailed = true
        }
    }

    func act(_ fix: Fix) {
        switch fix.kind {
        case .wait(let until):
            watcher.snooze(live, until: until)
        case .stop:
            confirmStop = fix
        case .lookUp(let name):
            watcher.log("Look it up pressed for \(live.reportSubject)")
            // only the process name is searched for: no paths, nothing about this Mac
            var u = URLComponents(string: "https://duckduckgo.com/")!
            u.queryItems = [URLQueryItem(name: "q", value: "macOS \(name) high CPU")]
            if let url = u.url { NSWorkspace.shared.open(url) }
        case .cooler:
            // background priority: macOS runs it on the efficiency cores and slows its disk use; checked and undoable
            show(watcher.setCooler(live, on: !watcher.isCooled(live)))
        case .quitApp(let bundle):
            // found by where the app is installed, not by its display name (which can differ, or be shared)
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == bundle }) {
                let ok = app.terminate()
                let name = app.localizedName ?? "The app"
                if ok { note = "Asked \(name) to quit."; noteFailed = false }
                else { note = "\(name) didn't quit. It may be asking you something."; noteFailed = true }
                watcher.log("Quit pressed for \(live.reportSubject): " + (ok ? "asked to quit" : "didn't quit"))
            } else { note = "It's already closed."; noteFailed = false }
        case .share:
            if !sharing { watcher.log("Share this case opened for \(live.reportSubject)") }
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
            Text("This is everything we'd share:")
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
            Text("Nothing is posted until you press Submit on GitHub. No GitHub account? Use Copy.")
                .font(.caption2).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// "Report a problem": what kind, what happened in the person's words, and the full report shown before anything
/// leaves. Open in GitHub sends it to GitHub in the link and opens the form there; Copy keeps it on the Mac.
struct ProblemView: View {
    let watcher: Watcher
    @State private var kind = ProblemReport.kinds[0]
    @State private var words = ""
    @State private var copied = false

    var report: String { ProblemReport.make(kind: kind, words: words, activity: watcher.activity, cards: watcher.cards, mac: watcher.mac) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Report a problem").font(.body.weight(.semibold))
            Picker("What went wrong?", selection: $kind) { ForEach(ProblemReport.kinds, id: \.self) { Text($0) } }
                .pickerStyle(.radioGroup).font(.callout)
            Text("Tell us more (optional). It's public, so skip anything private.")
                .font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $words)
                .font(.callout)
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.edge, lineWidth: 1))
            Text("We'll also send what Cool Head did lately:")
                .font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(report.replacingOccurrences(of: "**", with: ""))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Ink.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 130)
            .padding(8)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Button("Open in GitHub") {
                    watcher.log("Report a problem sent to GitHub")
                    if let u = ProblemReport.issueURL(kind: kind, words: words, report: report) { NSWorkspace.shared.open(u) }
                    watcher.showReport = false
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Problem: \(kind)\n\n\(words)\n\n\(report)", forType: .string)
                    copied = true
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button("Cancel") { watcher.showReport = false }.buttonStyle(.plain).font(.callout).foregroundStyle(Ink.muted)
            }
            Text("Nothing is posted until you press Submit on GitHub. No GitHub account? Use Copy.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }
}

/// The name and version at the top right, which is also the "check for updates" button: click it to check, and if
/// there is a newer version it downloads, verifies and installs it. It says what it is doing in place, briefly.
struct VersionButton: View {
    let updater = Updater.shared
    @State private var hovering = false
    @State private var spin = false

    var body: some View {
        Button {
            Task {
                await updater.check(quiet: false)
                if case .available = updater.phase { await updater.install() }
            }
        } label: {
            HStack(spacing: 4) {
                switch updater.phase {
                case .checking:
                    spinner
                    Text("Checking for updates…")
                case .installing:
                    spinner
                    Text("Downloading the update…")
                case .upToDate:
                    Image(systemName: "checkmark.circle")
                    Text("Up to date")
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                    Text("Couldn't update")
                case .available(let v):
                    Image(systemName: "arrow.down.circle")
                    Text("v\(v) available")
                case .idle:
                    if hovering { Image(systemName: "arrow.triangle.2.circlepath") }
                    Text("Cool Head v\(CoolHead.version)")
                }
            }
            .font(.caption2)
            .foregroundStyle(hovering ? Ink.text : Ink.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Check for updates")
        .accessibilityLabel("Cool Head \(CoolHead.version). Check for updates")
        .disabled(updater.phase == .checking || updater.phase == .installing)
    }

    var spinner: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
            .onDisappear { spin = false }
    }
}

/// Shown once, on first launch, when the panel opens by itself: Cool Head has no window, and this is where it lives.
struct WelcomeCard: View {
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "snowflake").font(.title3).foregroundStyle(Color.accentColor)
                Text("Cool Head lives up here, in your menu bar.").font(.body.weight(.semibold))
            }
            Text("No window to keep open. It quietly watches your Mac and tells you why it's hot or slow.")
                .font(.callout).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                badgeLine("circle.fill", .systemGreen, "All good")
                badgeLine("exclamationmark.triangle.fill", NSColor(srgbRed: 1.0, green: 0.74, blue: 0.0, alpha: 1), "Worth watching")
                badgeLine("xmark.octagon.fill", .systemRed, "Problem")
            }
            Text("Click the snowflake to open. Right-click for more.")
                .font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            Button("Got it", action: done).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    func badgeLine(_ symbol: String, _ color: NSColor, _ meaning: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Color(nsColor: color)).frame(width: 16)
            Text(meaning).font(.callout).foregroundStyle(Ink.text)
        }
    }
}

/// A line at the top of the panel about updates: shown only when there is something to say.
struct UpdateBanner: View {
    let updater = Updater.shared

    var body: some View {
        switch updater.phase {
        case .available(let v):
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle").foregroundStyle(Color.accentColor)
                Text("Cool Head \(v) is available.").font(.callout.weight(.medium))
                Spacer()
                if let page = updater.releasePage {
                    Button("What's new") { NSWorkspace.shared.open(page) }.buttonStyle(.plain).font(.callout).foregroundStyle(Ink.muted)
                }
                Button("Install") { Task { await updater.install() } }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        case .installing, .checking, .upToDate:
            EmptyView()          // the version label at the top right says these
        case .failed(let why):
            Label(why, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }
}

/// A process running cooler because the person chose it: pinned at the top until it ends or is set back, so it
/// is clear what Cool Head has changed. Reporting a problem with it sits beside it.
struct PinnedRow: View {
    let item: Watcher.CooledItem
    let watcher: Watcher
    @State private var failed: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tortoise.fill").foregroundStyle(Color.accentColor).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(item.name) is running cooler").font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("Since \(Fmt.time(item.since)). Slower, but cooler.").font(.caption).foregroundStyle(Ink.muted)
                if let f = failed { Text(f).font(.caption).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Button { if case .failed(let why) = watcher.restore(item) { failed = "That didn't work: \(why)." } } label: {
                    Label("Back to full speed", systemImage: "hare")
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button("Report a problem") { watcher.showReport = true }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 10)
        .frozen()
    }
}

/// A "frozen" frame for things Cool Head has cooled: an icy gradient edge, a frosty tint, and icicles along the top.
struct Frozen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LinearGradient(colors: [Color(red: 0.86, green: 0.95, blue: 1.0).opacity(0.35), Color(red: 0.70, green: 0.88, blue: 1.0).opacity(0.18)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.85, blue: 1.0), Color(red: 0.30, green: 0.65, blue: 0.95), .white],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
            .overlay(alignment: .top) { Icicles().frame(height: 9).padding(.horizontal, 12).allowsHitTesting(false) }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "snowflake").font(.system(size: 9)).foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0)).padding(5)
            }
    }
}

extension View { func frozen() -> some View { modifier(Frozen()) } }

/// A row of icicles of uneven length, hanging from the top edge.
struct Icicles: View {
    var body: some View {
        Canvas { ctx, size in
            let lengths: [CGFloat] = [0.9, 0.5, 1.0, 0.35, 0.75, 0.55, 0.95, 0.4, 0.8, 0.5, 1.0, 0.6, 0.45, 0.85]
            let w = size.width / CGFloat(lengths.count)
            for (i, l) in lengths.enumerated() {
                var p = Path()
                let x = CGFloat(i) * w
                p.move(to: CGPoint(x: x + w * 0.15, y: 0))
                p.addLine(to: CGPoint(x: x + w * 0.85, y: 0))
                p.addLine(to: CGPoint(x: x + w * 0.5, y: size.height * l))
                p.closeSubpath()
                ctx.fill(p, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.62, green: 0.87, blue: 1.0)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
    }
}

/// One option: a button with what it would cause underneath. The recommended one stands out.
struct FixRow: View {
    let fix: Fix
    let cooled: Bool
    let run: (Fix) -> Void

    /// A picture for each kind of option, so the list scans at a glance.
    var icon: String {
        switch fix.kind {
        case .wait: return "clock"
        case .stop: return "stop.circle"
        case .cooler: return cooled ? "hare" : "tortoise"
        case .lookUp: return "magnifyingglass"
        case .quitApp: return "xmark.circle"
        case .share: return "square.and.arrow.up"
        case .info: return "lightbulb"
        }
    }

    var opensBrowser: Bool { if case .lookUp = fix.kind { return true }; return false }

    /// Once it is already running cooler, "Back to full speed" isn't the recommendation.
    var recommended: Bool {
        if fix.kind == .cooler && cooled { return false }
        if case .wait = fix.kind, cooled, cooledCardRecommendedCooler { return true }     // waiting takes over
        return fix.recommended
    }
    /// Set by the card: it is running cooler and cooling was what had been recommended.
    var cooledCardRecommendedCooler = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if fix.kind == .info {
                Label(fix.title, systemImage: "lightbulb").font(.callout.weight(.medium))
            } else {
                Button { run(fix) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icon).frame(width: 18)
                        Text(fix.kind == .cooler && cooled ? "Back to full speed" : fix.title)
                        Spacer(minLength: 0)
                        if opensBrowser { Image(systemName: "arrow.up.right.square").foregroundStyle(Ink.muted).help("Opens in your browser") }
                    }
                }
                .buttonStyle(.bordered)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(recommended ? Color.accentColor : .clear, lineWidth: 1.5))
                .controlSize(.regular)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if recommended { Text("Recommended").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                let line = fix.kind == .cooler && cooled ? "Runs at normal speed again." : fix.consequence
                if !line.isEmpty {
                    Text(line).font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Along the bottom: the two settings as switches, then Activity Monitor, About and Quit as line icons.
struct BottomBar: View {
    let watcher: Watcher
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
                IconButton(symbol: "exclamationmark.bubble", tip: "Report a problem") { watcher.showReport.toggle() }
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

/// The scrolling middle's natural height, so the panel can fit it exactly until it reaches the limit.
struct MiddleHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
