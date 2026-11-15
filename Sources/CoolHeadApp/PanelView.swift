import AppKit
import CoolHeadCore
import SwiftUI

struct PanelView: View {
    let watcher: Watcher
    @AppStorage("welcomed") private var welcomed = false
    // a screenshot limited to some cards shows neither, so it shows the cards as anyone would see them day to day
    @State private var whatsNew = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] != nil ? nil : WhatsNew.pending

    /// The middle scrolls; the panel grows with it up to this height, so it stays easy to read.
    static var maxMiddle: CGFloat { min(560, (NSScreen.main?.visibleFrame.height ?? 900) * 0.62) }
    @State private var middleHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // fixed at the top
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: Badge.symbol(level))
                    .foregroundStyle(Color(nsColor: Badge.color(level)))
                    .accessibilityLabel(level == .good ? "All good" : level == .warning ? "Worth watching" : "Problem")
                Text(status).font(.headline)
                Spacer()
                VersionButton()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider()
            // scrolls once it is taller than the limit
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !welcomed && ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] == nil { WelcomeCard { welcomed = true; WhatsNew.markSeen() } }
                    else if let notes = whatsNew { WhatsNewCard(notes: notes) { WhatsNew.markSeen(); whatsNew = nil } }
                    UpdateBanner()
                    ForEach(watcher.notices, id: \.self) { n in
                        Label(n, systemImage: "hare").font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(watcher.pausedJobs) { PausedJobRow(job: $0, watcher: watcher) }
                    ForEach(watcher.syncPauses) { SyncPauseRow(pause: $0, watcher: watcher) }
                    ForEach(watcher.cooledList) { PinnedRow(item: $0, watcher: watcher) }
                    if watcher.showReport {
                        ProblemView(watcher: watcher)
                    } else if shownCards.isEmpty && !watcher.syncPauses.contains(where: { $0.until <= Date() }) {
                        Text(watcher.mac.cores == 0 ? "Taking a first look…" : "Nothing needs a look.")
                            .foregroundStyle(Ink.muted)
                    } else {
                        ForEach(shownCards) { CardView(live: $0, watcher: watcher) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(watcher.panelSession)          // rebuilt after each close, so everything starts collapsed
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
    /// The header's level: the watcher's, except in a screenshot limited to some cards, where it follows only those.
    var level: Watcher.Level {
        guard ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] != nil else { return watcher.level }
        if shownCards.contains(where: { $0.severity >= 2 }) { return .issue }
        return shownCards.contains(where: { $0.needsLook || ($0.heatCause && !watcher.isCooled($0)) }) ? .warning : .good
    }

    var shownCards: [LiveCard] {
        guard let only = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] else { return watcher.cards }
        return watcher.cards.filter { $0.card.headline.contains(only) }
    }

    /// The heat word appears only when the Mac is warm or hot; otherwise the line is about what needs watching.
    var status: String {
        let n = shownCards.filter { $0.needsLook || ($0.heatCause && !watcher.isCooled($0)) }.count
            + watcher.syncPauses.filter { $0.until <= Date() }.count                    // syncing to resume
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(live.card.headline)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // waiting is a reminder, not an option: hide the card for a while; it comes back sooner if it gets worse
                Menu {
                    Text("Check back in…")
                    ForEach([(10, "10 minutes"), (30, "30 minutes"), (60, "1 hour")], id: \.0) { m, label in
                        Button(label) { watcher.snooze(live, until: Date().addingTimeInterval(Double(m) * 60)) }
                    }
                    if live.trustKey != nil {
                        Divider()
                        if Trust.contains(live.trustKey) {
                            Button("Stop trusting \(live.trustName)") { watcher.setTrusted(live, false) }
                        } else {
                            Button("Always trust \(live.trustName)") { watcher.setTrusted(live, true) }
                        }
                    }
                } label: { Image(systemName: "clock").foregroundStyle(Ink.muted) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Check back later")
                .accessibilityLabel("Check back later")
            }
            if let t = live.trustNote {
                Label(t, systemImage: live.trusted ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(live.trusted ? Ink.muted : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !live.card.fixes.isEmpty {
                // a warning offers fixes; a calm card only explains, with options if you want them anyway
                // worth watching (stuck, unexplained, or a cause of heat you can act on) gets Explore fixes, in orange
                let watch = live.needsLook || (live.heatCause && !watcher.isCooled(live))
                Button(open ? "Hide" : (watch ? "Explore fixes" : "Learn more")) {
                    withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(watch ? .orange : .accentColor)
                    .controlSize(.small)
            }
            if open {
                if !live.card.explanation.isEmpty {
                    Text(live.card.explanation)
                        .font(.callout).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(live.card.fixes) { f in
                        FixRow(fix: f, cooled: watcher.isCooled(live), run: { act($0) }, runUntil: { act($0, until: $1) })
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
            Button(confirmStop?.title ?? "Stop it", role: .destructive) { show(watcher.stop(live)); confirmStop = nil }
            Button("Cancel", role: .cancel) { confirmStop = nil }
        } message: {
            Text(confirmStop?.consequence ?? "")
        }
    }

    /// Names the process, so the person knows exactly what they are stopping.
    var stopTitle: String {
        // a browser tab or extension: say exactly that, not "Stop Google Chrome?"
        if let t = confirmStop?.title, t != "Stop it" { return t + "?" }
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

    func act(_ fix: Fix, until: Date? = nil) {
        switch fix.kind {
        case .pauseJob:
            show(watcher.pauseJob(live))
        case .pauseSync(let bundle, let name):
            // Cool Head can't pause a sync app itself: it opens it, and reminds you to resume (saved, so it survives a restart)
            guard let until else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: NSWorkspace.OpenConfiguration())
            watcher.addSyncPause(name: name, bundle: bundle, until: until)
            note = "Now pause it from \(name)'s menu bar icon. We'll remind you to resume at \(Fmt.time(until))."; noteFailed = false
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
        case .openPage(let bundle, let address):
            // Chrome refuses chrome:// addresses opened from another app (Chromium's url_util.cc allows only one), so the
            // address is copied and the browser brought forward, with the keys to press. Nothing changes until the
            // person switches something on that page.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: NSWorkspace.OpenConfiguration())
            let app = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            note = "Copied. In \(app), press ⌘L, then ⌘V, then Return."; noteFailed = false
            watcher.log("Copied a settings address for \(live.reportSubject)")
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

/// What's new in this version, shown once after an update that brought something worth telling.
struct WhatsNewCard: View {
    let notes: [String]
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What's new in \(CoolHead.version)", systemImage: "sparkles").font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(notes, id: \.self) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Ink.muted)
                        Text(n).font(.callout).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Got it", action: done).buttonStyle(.borderedProminent).controlSize(.small)
                Button("All notes") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ThePhilDiamond/CoolHead/blob/main/CHANGELOG.md")!)
                }
                .buttonStyle(.link).font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }
}

/// The notes the app shows after updating: only versions worth telling about have an entry. They're the short
/// versions of CHANGELOG.md.
enum WhatsNew {
    static let notes: [String: [String]] = [
        "0.4.4": [
            "Security software is never stopped or slowed.",
            "Pause syncing for a set time, with a reminder to resume.",
            "On battery, pause a heavy job until you plug in. Nothing is lost. Turn this off from the right-click menu.",
        ],
        "0.4.3": [
            "Chrome without quitting it: slow just the busy tab, turn on Energy Saver, or turn off an extension.",
            "Close just one tab before ever quitting the whole browser.",
        ],
        "0.4.2": [
            "Games are recognised as games, and never slowed down.",
            "While you play, other busy work is offered to run cooler, to leave the game more power.",
        ],
        "0.4.1": [
            "A warm Mac now shows what's warming it, with something to do.",
            "The recommended option comes first and is marked.",
            "Check back later from the clock on any card.",
            "Always trust an app or job from the clock. It's still flagged if it looks stuck, your Mac gets hot, or it runs for 8 hours.",
        ],
        "0.4.0": [
            "Shorter cards: one sentence, then Explore fixes or Learn more.",
            "A green note says what changed after you act.",
            "Things you slow down stay pinned at the top, frosted.",
            "Better memory advice: close heavy tabs, Memory Saver, or quit, with what each costs.",
            "Try the Melting Snowflake icon: right-click the menu bar icon.",
        ],
    ]

    /// Notes for this version, if it's newer than the last version seen and has any.
    static var pending: [String]? {
        guard UserDefaults.standard.bool(forKey: "welcomed") else { return nil }          // new users get the welcome
        let last = UserDefaults.standard.string(forKey: "lastSeenVersion") ?? "0"
        guard Updater.newer(CoolHead.version, than: last) else { return nil }
        guard let n = notes[CoolHead.version] else { markSeen(); return nil }             // nothing worth telling
        return n
    }

    static func markSeen() { UserDefaults.standard.set(CoolHead.version, forKey: "lastSeenVersion") }
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
        .padding(.horizontal, 36).padding(.vertical, 20)       // text sits in the clear middle, well off the frost
        // the icon as a large, faint watermark, well inside the frost (Phil, 15 November 2026)
        .background(alignment: .leading) {
            Image(systemName: "tortoise.fill").font(.system(size: 56)).foregroundStyle(Color.primary.opacity(0.2))
                .padding(.leading, 40).accessibilityHidden(true)
        }
        .frozen()
    }
}

/// A job paused until the Mac is plugged in: frozen, literally, so it wears the frost.
struct PausedJobRow: View {
    let job: PausedJob
    let watcher: Watcher
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(job.name) is paused until you plug in").font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("Since \(Fmt.time(job.since)). Nothing is lost.").font(.caption).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 4)
            Button { watcher.resumeJob(job, why: "Resume now pressed") } label: { Label("Resume now", systemImage: "play") }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 36).padding(.vertical, 20)
        .background(alignment: .leading) {
            Image(systemName: "pause.circle.fill").font(.system(size: 56)).foregroundStyle(Color.primary.opacity(0.2))
                .padding(.leading, 40).accessibilityHidden(true)
        }
        .frozen()
    }
}

/// A sync app the person paused from Cool Head: when to resume, and once that time comes, a nudge.
struct SyncPauseRow: View {
    let pause: SyncPause
    let watcher: Watcher
    var body: some View {
        let due = pause.until <= Date()
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: due ? "exclamationmark.circle" : "pause.circle").foregroundStyle(due ? Color.orange : Ink.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(due ? "Time to resume \(pause.name) syncing" : "\(pause.name) is paused").font(.callout.weight(.semibold))
                Text(due ? "Resume it from its menu bar icon." : "We'll remind you to resume at \(Fmt.time(pause.until)).")
                    .font(.caption).foregroundStyle(due ? Color.orange : Ink.muted)
            }
            Spacer(minLength: 4)
            Button("Resumed") { watcher.syncResumed(pause.name) }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(12)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(due ? Color.orange.opacity(0.6) : Ink.edge, lineWidth: 1))
    }
}

/// A "frozen" frame for things Cool Head has cooled: frost growing in from the edges, as on a cold window, on an ice
/// tint. No snowflake symbols: Phil, 15 November 2026, "We don't want too many "snowflakes" in the frame as it will
/// look like Christmas season - we want cold/chill/frozen vibes". All vector lines, drawn from a fixed pattern, so it looks the same every time and costs almost nothing.
struct Frozen: ViewModifier {
    static let ice = Color(red: 0.55, green: 0.82, blue: 1.0)

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(IceTint.color)
                    Frost().clipShape(RoundedRectangle(cornerRadius: 10))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 0.70, green: 0.88, blue: 1.0).opacity(0.9), lineWidth: 1))
    }
}

extension View { func frozen() -> some View { modifier(Frozen()) } }

/// Pale ice blue, deep enough in light mode for white frost to show, and a cool slate in dark mode.
enum IceTint {
    static let color = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.20, green: 0.30, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.56, green: 0.75, blue: 0.94, alpha: 1)
    })
}

/// Frost on a cold window, as people know it: a frosted rim hugging the edges of the glass, thickest in the corners
/// and fading through a soft, uneven inner edge into clear glass, with a few feather-like crystals reaching in and
/// some sparkles. Vector shapes from a fixed pattern, so it never shimmers and costs almost nothing.
struct Frost: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var seed: UInt64 = 0xF2057
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 10_000) / 10_000
            }
            let phases = (0..<4).map { _ in rnd() * 6.28 }
            // smooth, uneven variation along the edge, 0 to 1
            func wobble(_ s: CGFloat) -> CGFloat {
                // long drifts plus smaller bumps, so the frost line rises and dips along each side
                let v = 0.4 * sin(s * 0.05 + phases[3]) + 0.3 * sin(s * 0.17 + phases[0]) + 0.2 * sin(s * 0.43 + phases[1]) + 0.1 * sin(s * 1.07 + phases[2])
                return (v + 1) / 2
            }
            // closeness to the nearest corner, 1 at the corner, 0 beyond `reach`
            func cornerness(_ x: CGFloat, _ y: CGFloat, reach: CGFloat) -> CGFloat {
                let d = min(hypot(x, y), hypot(w - x, y), hypot(x, h - y), hypot(w - x, h - y))
                return max(0, 1 - d / reach)
            }
            // the inner edge of a frost band: walk round the rectangle, pushing inward by an uneven amount
            func band(base: CGFloat, vary: CGFloat, corner: CGFloat, bottomExtra: CGFloat) -> Path {
                var pts: [CGPoint] = []
                let step: CGFloat = 3
                var s: CGFloat = 0
                func add(_ x: CGFloat, _ y: CGFloat, _ nx: CGFloat, _ ny: CGFloat) {
                    let c = cornerness(x, y, reach: 34)
                    let extra = ny < 0 ? bottomExtra : 0                    // frost settles thicker at the bottom
                    let d = base + vary * wobble(s) + corner * c * c + extra
                    pts.append(CGPoint(x: x + nx * d, y: y + ny * d))
                    s += step
                }
                var x: CGFloat = 0, y: CGFloat = 0
                while x < w { add(x, 0, 0, 1); x += step }
                while y < h { add(w, y, -1, 0); y += step }
                while x > 0 { add(x, h, 0, -1); x -= step }
                while y > 0 { add(0, y, 1, 0); y -= step }
                var p = Path(CGRect(origin: .zero, size: size))
                // a smooth curve through the midpoints, so the edge is soft rather than jagged
                guard pts.count > 2 else { return p }
                let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
                p.move(to: mid(pts[pts.count - 1], pts[0]))
                for i in 0..<pts.count { p.addQuadCurve(to: mid(pts[i], pts[(i + 1) % pts.count]), control: pts[i]) }
                p.closeSubpath()
                return p
            }
            let even = FillStyle(eoFill: true)
            // blurred, so the frost fades into the glass instead of stepping like a contour map
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(band(base: 8, vary: 11, corner: 24, bottomExtra: 6), with: .color(.white.opacity(0.32)), style: even)   // haze
                layer.fill(band(base: 4, vary: 8, corner: 18, bottomExtra: 3), with: .color(.white.opacity(0.5)), style: even)
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.8))
                layer.fill(band(base: 2, vary: 6, corner: 12, bottomExtra: 2), with: .color(.white.opacity(0.92)), style: even) // the rim
            }

            // fern frost: a gently curving stem with side branches that alternate and shorten toward the tip, each
            // branch feathered with fine barbs, as frost grows across a cold pane
            func feather(_ from: CGPoint, _ angle: CGFloat, _ length: CGFloat, into path: inout Path) {
                let n = max(2, Int(length / 1.4))
                var p = from
                path.move(to: p)
                for i in 0..<n {
                    let t = CGFloat(i) / CGFloat(n)
                    let next = CGPoint(x: p.x + cos(angle) * 1.4, y: p.y + sin(angle) * 1.4)
                    path.addLine(to: next)
                    if i > 0 {
                        let barb = (1 - t) * length * 0.36 + 0.6
                        for side in [-1.0, 1.0] as [CGFloat] {
                            let ba = angle + side * 0.7
                            path.move(to: next)
                            path.addLine(to: CGPoint(x: next.x + cos(ba) * barb, y: next.y + sin(ba) * barb))
                            path.move(to: next)
                        }
                    }
                    p = next
                }
            }
            func fern(from: CGPoint, angle: CGFloat, length: CGFloat, curl: CGFloat) {
                var stem = Path(), branches = Path()
                let n = Int(length / 1.6)
                var p = from, a = angle
                stem.move(to: p)
                for i in 0..<n {
                    let t = CGFloat(i) / CGFloat(n)
                    a += curl / CGFloat(n)
                    let next = CGPoint(x: p.x + cos(a) * 1.6, y: p.y + sin(a) * 1.6)
                    stem.addLine(to: next)
                    if i % 2 == 1 && t < 0.94 {
                        for side in [-1.0, 1.0] as [CGFloat] {
                            let len = ((1 - t) * length * 0.4 + 2) * (0.7 + rnd() * 0.3)
                            feather(next, a + side * (0.7 + rnd() * 0.25), len, into: &branches)
                        }
                    }
                    p = next
                }
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 1.4))
                    glow.stroke(branches, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
                ctx.stroke(branches, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                ctx.stroke(stem, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
            }
            // in the corners only, where frost gathers; the middle stays clear (Phil, 15 November 2026)
            fern(from: CGPoint(x: 4, y: h - 4), angle: -.pi / 3.2, length: min(50, h * 0.72), curl: 0.45)
            fern(from: CGPoint(x: 6, y: h - 3), angle: -0.35, length: min(30, h * 0.42), curl: -0.3)
            fern(from: CGPoint(x: w - 5, y: h - 4), angle: -.pi + .pi / 4, length: min(42, h * 0.62), curl: -0.4)
            fern(from: CGPoint(x: w - 6, y: h - 3), angle: -.pi + 0.3, length: min(24, h * 0.36), curl: 0.3)
            fern(from: CGPoint(x: 4, y: 4), angle: .pi / 4.5, length: min(26, h * 0.4), curl: 0.3)
            fern(from: CGPoint(x: w - 4, y: 4), angle: .pi - .pi / 4, length: min(22, h * 0.36), curl: -0.3)

            // sparkles near the frost: dots, and a few four-pointed glints
            for i in 0..<14 {
                let side = rnd()
                let pt = side < 0.45 ? CGPoint(x: rnd() * w, y: h - 6 - rnd() * 12)
                    : side < 0.6 ? CGPoint(x: rnd() * w, y: 4 + rnd() * 8)
                    : CGPoint(x: side < 0.8 ? 4 + rnd() * 12 : w - 4 - rnd() * 12, y: rnd() * h)
                if i % 7 == 6 {
                    let r = 1.6 + rnd() * 0.8
                    var star = Path()
                    star.move(to: CGPoint(x: pt.x, y: pt.y - r))
                    star.addQuadCurve(to: CGPoint(x: pt.x + r, y: pt.y), control: pt)
                    star.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y + r), control: pt)
                    star.addQuadCurve(to: CGPoint(x: pt.x - r, y: pt.y), control: pt)
                    star.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y - r), control: pt)
                    ctx.fill(star, with: .color(.white.opacity(0.95)))
                } else {
                    let r = 0.6 + rnd() * 0.9
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9)))
                }
            }
        }
        .allowsHitTesting(false)
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
        case .openPage: return "gearshape"
        case .pauseJob, .pauseSync: return "pause.circle"
        }
    }
    /// For Pause syncing: how long, before anything happens.
    var runUntil: (Fix, Date) -> Void = { _, _ in }
    @State private var choosing = false
    var isSyncPause: Bool { if case .pauseSync = fix.kind { return true }; return false }
    /// 1 hour, 3 hours, and until 8pm while that is more than an hour away.
    var pauseChoices: [(String, Date)] {
        let now = Date()
        var out: [(String, Date)] = [("1 hour", now.addingTimeInterval(3600)), ("3 hours", now.addingTimeInterval(3 * 3600))]
        if let eight = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: now), eight.timeIntervalSince(now) > 3600 * 3.5 {
            out.append(("Until \(Fmt.time(eight))", eight))
        }
        return out
    }

    var opensBrowser: Bool { if case .lookUp = fix.kind { return true }; return false }

    /// Once it is already running cooler, "Back to full speed" isn't the recommendation.
    var recommended: Bool { fix.kind == .cooler && cooled ? false : fix.recommended }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if fix.kind == .info {
                HStack(spacing: 6) {
                    Label(fix.title, systemImage: "lightbulb").font(.callout.weight(recommended ? .bold : .medium))
                    if recommended { RecommendedTag(onAccent: false) }
                }
            } else {
                // the recommended option is the filled button, in bold, tagged; the rest are plain
                let button = Button { if isSyncPause { withAnimation(.easeOut(duration: 0.15)) { choosing.toggle() } } else { run(fix) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icon).frame(width: 18)
                        Text(fix.kind == .cooler && cooled ? "Back to full speed" : fix.title).fontWeight(recommended ? .bold : .regular)
                        if recommended { RecommendedTag(onAccent: true) }
                        Spacer(minLength: 0)
                        if opensBrowser { Image(systemName: "arrow.up.right.square").opacity(0.7).help("Opens in your browser") }
                    }
                }
                .controlSize(.regular)
                if recommended { button.buttonStyle(RecommendedButton()) } else { button.buttonStyle(.bordered) }
                if choosing {
                    HStack(spacing: 6) {
                        Text("For").font(.callout).foregroundStyle(Ink.muted)
                        ForEach(pauseChoices, id: \.0) { label, until in
                            Button(label) { choosing = false; runUntil(fix, until) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                let line = fix.kind == .cooler && cooled ? "Runs at normal speed again." : fix.consequence
                if !line.isEmpty {
                    Text(line).font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The recommended option: filled with the accent colour, white text, whether or not the panel is the active window
/// (macOS greys its own prominent buttons in an inactive window).
struct RecommendedButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1)))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

/// "Recommended", as a small rounded tag beside the option's name.
struct RecommendedTag: View {
    let onAccent: Bool
    var body: some View {
        Text("Recommended")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .foregroundStyle(onAccent ? Color.accentColor : .white)
            .background(Capsule().fill(onAccent ? Color.white.opacity(0.92) : Color.accentColor))
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
