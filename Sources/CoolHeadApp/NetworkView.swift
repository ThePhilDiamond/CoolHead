import AppKit
import CoolHeadCore
import SwiftUI

/// "Test my network", one of the tools along the bottom of the panel, shown in the panel's middle. Opening it reads
/// what the Mac can say about its connection (no prompt, about a second); Apple's test runs only when Start test is
/// pressed. A test that's started carries on when another tool opens or the panel closes, and its results wait here
/// (Phil, 19 November 2026: "the network test should continue, complete, and store the results in the background.
/// Otherwise the work is wasted"); only Stop, or Cool Head quitting, stops it.
@MainActor
final class NetworkTester: ObservableObject {
    static let shared = NetworkTester()

    enum Phase: Equatable { case reading, ready, testing(started: Date), done(NetworkCheck.Outcome) }

    @Published var shown = false
    @Published private(set) var phase = Phase.reading
    @Published private(set) var setup: NetworkCheck.Setup?
    /// Where websites see the Mac, asked of Cloudflare as part of the test; nil before.
    @Published private(set) var seen: NetworkCheck.Where?
    /// When the last test finished. Its results stay for `keep` after the panel or the view closes, so someone on the
    /// phone with their internet provider can look elsewhere and come back to them (Phil, 19 November 2026: "let's have
    /// the network test results persist for 30 minutes and add a date-timestamp, even if the user closes the Cool Head pane").
    @Published private(set) var finished: Date?
    static let keep: TimeInterval = 30 * 60
    /// A test finished while the view was closed, and its results haven't been looked at yet: the Network tool shows a
    /// dot in the result's color until they are (Phil, 19 November 2026: "Yes, render it").
    @Published private(set) var unseen = false
    private var work: Task<Void, Never>?

    /// A finished test's results, still within `keep`.
    var resultsKept: Bool {
        guard case .done = phase, let f = finished else { return false }
        return Date().timeIntervalSince(f) < NetworkTester.keep
    }

    /// A test is running, seen or not.
    var running: Bool { if case .testing = phase { return true }; return false }

    /// The level of results that finished out of sight and are still kept (0 good, 1 fair, 2 poor), for the tool's dot.
    var readyLevel: Int? {
        guard unseen, resultsKept, case .done(let outcome) = phase else { return nil }
        return NetworkCheck.verdict(outcome).level
    }

    /// Opens the view: a test still running, or the last results if they're under 30 minutes old; otherwise reads the
    /// connection, and nothing is sent.
    func open() {
        shown = true
        unseen = false
        if running || resultsKept { return }
        finished = nil
        phase = .reading
        seen = nil
        work?.cancel()
        work = Task {
            let s = await Task.detached { NetworkCheck.readSetup() }.value
            guard !Task.isCancelled else { return }
            setup = s
            phase = .ready
        }
    }

    /// Runs Apple's test, and asks Cloudflare where websites see the Mac alongside it (a few hundred bytes, so it
    /// doesn't disturb the measurement). Who was using the network is read again first, since the test itself fills it.
    func start() {
        work?.cancel()
        phase = .testing(started: Date())
        seen = nil
        finished = nil
        work = Task {
            let s = await Task.detached { NetworkCheck.readSetup() }.value
            guard !Task.isCancelled else { return }
            setup = s
            async let place = Task.detached { NetworkCheck.whereSeen(s) }.value
            let outcome = await NetworkCheck.run()
            guard !Task.isCancelled else { return }
            seen = await place
            guard !Task.isCancelled else { return }
            phase = .done(outcome)
            finished = Date()
            unseen = !shown
        }
    }

    /// Stops a running test and goes back to the start.
    func stop() {
        work?.cancel()
        phase = setup == nil ? .reading : .ready
        if setup == nil { open() }
    }

    /// Closes the view. A test still running carries on and keeps its results; finished results are kept for `keep`.
    func close() {
        shown = false
        if running || resultsKept { return }
        work?.cancel()
        work = nil
        seen = nil
        finished = nil
        phase = .reading
    }

    /// Stops whatever is running, for when Cool Head quits (macOS doesn't stop a program's children when it quits).
    func halt() {
        work?.cancel()
        work = nil
    }

    /// For renders: show a given state without reading or testing.
    func show(_ phase: Phase, setup: NetworkCheck.Setup, seen: NetworkCheck.Where? = nil) {
        work?.cancel()
        self.setup = setup
        self.seen = seen
        self.phase = phase
        if case .done = phase { finished = Date() } else { finished = nil }
        shown = true
    }

    /// For renders: the view closed with the test still running, or with its results not yet looked at.
    func showAway() {
        shown = false
        if case .done = phase { unseen = true }
    }
}

struct NetworkView: View {
    @ObservedObject var tester: NetworkTester
    let watcher: Watcher
    @State private var note: String?
    @State private var allFixes = false
    @State private var signalNumbers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Test my network", systemImage: "network").font(.body.weight(.semibold))
                Spacer()
                Button { tester.close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            // one layout from the moment it opens, the same in every state: placeholders that turn into the data, so the
            // page never grows as it goes (Phil, 16 November 2026: "We should have the fixed layout upon opening it, can
            // show it's checking the connection, and then populate the data. But starting small and then expanding is
            // jarring and not elegant."). Only fixes for a real problem add to it, after a test.
            let result: NetworkCheck.Result? = { if case .done(.done(let r)) = tester.phase { return r }; return nil }()
            status
            HStack(spacing: 8) {
                signalTile
                speedTiles(result)
            }
            if let s = tester.setup, s.proxy || s.autoProxy {
                HStack(spacing: 6) { chip("Proxy", "arrow.triangle.branch") }
            }
            meter(result)
            taskRow(result)
            privacy
            actionRow
            if let r = result {
                // the one fact the old Nerdy stuff held that nothing else shows, and only when it's the problem
                // (Phil, 16 November 2026: "if any of it is useful it can show when the tests run")
                if case .none = tester.setup?.dns {
                    Label("No server is set to look up website names, so sites won't load by name.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
                }
                fixList(r)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    // MARK: pieces

    static func color(_ level: Int) -> Color { [Color.green, .yellow, .orange][min(max(level, 0), 2)] }
    /// A result's mark, in the top line and on the Network tool when results wait: good, fair, or poor.
    static func mark(_ level: Int) -> String { ["checkmark.circle.fill", "minus.circle.fill", "exclamationmark.triangle.fill"][min(max(level, 0), 2)] }

    var testing: Bool { if case .testing = tester.phase { return true }; return false }

    /// The top line, the same height in every state: checking, ready, testing (with the time left), or the answer.
    @ViewBuilder var status: some View {
        HStack(alignment: .top, spacing: 9) {
            switch tester.phase {
            case .reading:
                statusText("ellipsis.circle", Ink.muted, "Checking your connection…", "Nothing is sent until you start the test.")
            case .ready where tester.setup?.selfAssigned == true:
                // the one reading that means the Mac can't go online at all, so it takes the top line
                statusText("exclamationmark.triangle.fill", Color.orange, "The router didn't give this Mac an address",
                           "So it can't go online. Turn Wi-Fi off and on, or restart the router.")
            case .ready:
                let busy = tester.setup?.talkers.filter { $0.bytesPerSecond >= NetworkCheck.talkerFloor }.prefix(2) ?? []
                statusText("play.circle", Ink.muted, "Ready to test",
                           busy.isEmpty ? "Nothing else is using much of the network."
                               : "Using it now: " + busy.map { "\($0.name) (\(NetworkCheck.rate($0.bytesPerSecond).replacingOccurrences(of: " a second", with: "/s")))" }.joined(separator: ", ") + ".")
            case .testing(let started):
                TimelineView(.periodic(from: started, by: 1)) { t in
                    let left = max(1, NetworkCheck.testSeconds - Int(t.date.timeIntervalSince(started)))
                    statusText("arrow.triangle.2.circlepath", Color.accentColor, "Testing…", "About \(left) seconds left. Calls and downloads may slow for a moment.")
                }
            case .done(let outcome):
                let v = NetworkCheck.verdict(outcome)
                // the answer, then what it means in plain words: what the connection is fine for and only what isn't
                // (Phil, 16 November 2026); when it's fine, that the Mac, not the network, is where to look
                let meaning: String = {
                    guard case .done(let r) = outcome, let s = tester.setup else { return v.meaning }
                    return NetworkCheck.summary(r, s.link) + (v.level == 0 ? " If the Mac feels slow, look at the Mac." : "")
                }()
                // when, with the date, so it can be read out on a call later (kept 30 minutes)
                statusText(NetworkView.mark(v.level), NetworkView.color(v.level), v.title, meaning)
            }
        }
        .frame(minHeight: 50, alignment: .top)      // room for a two-line explanation, so every state is the same height
    }

    /// "2:41pm on 19 November 2026": always with the date.
    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.component(.minute, from: d) == 0 ? "ha" : "h:mma"
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "d MMMM yyyy"
        return "\(f.string(from: d).lowercased()) on \(day.string(from: d))"
    }

    func statusText(_ symbol: String, _ tint: Color, _ title: String, _ meaning: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(meaning).font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The signal, large and first, as a picture and a word (Phil, 16 November 2026: "signal strength numbers are less
    /// important, but a clear visual indicator of the signal strength large and up front like the speed and quality
    /// indicators is important"); the numbers are in its tooltip. Its bars cycle while the connection is read.
    @ViewBuilder var signalTile: some View {
        if tester.phase == .reading || tester.setup == nil {
            tileFrame {
                TimelineView(.periodic(from: .now, by: 0.35)) { t in
                    let step = Int(t.date.timeIntervalSinceReferenceDate / 0.35) % 4
                    Image(systemName: "wifi", variableValue: Double(step) / 3).font(.title3).foregroundStyle(Ink.muted)
                }
            } unit: { Text("signal") }
        } else if let s = tester.setup {
            let sig = NetworkView.signal(s.link)
            // a click shows the numbers in the same space, and another shows the word again (Phil, 16 November 2026: "if
            // a user clicks the signal box should we show the detailed numbers?")
            tileFrame {
                HStack(spacing: 5) {
                    Image(systemName: sig.symbol, variableValue: sig.strength).font(.title3).foregroundStyle(NetworkView.color(sig.level))
                    Text(signalNumbers ? sig.numbers : sig.word).font(.system(.callout, design: .rounded).weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.7).monospacedDigit()
                }
            } unit: { Text(signalNumbers ? sig.channel : sig.unit) }
            .contentShape(Rectangle())
            .onTapGesture { signalNumbers.toggle() }
            .help(sig.detail + (signalNumbers ? ". Click for the word." : ". Click for the numbers."))
            .accessibilityAddTraits(.isButton)
        }
    }

    /// Signal strength in a word: Strong from -67 dBm, Fair down to the -75 dBm where a Mac starts looking for a better
    /// access point (`NetworkCheck.weakSignal`), Weak below that. The thresholds are Cool Head's own.
    static func signal(_ link: NetworkCheck.Link)
        -> (symbol: String, strength: Double, word: String, unit: String, level: Int, detail: String, numbers: String, channel: String) {
        switch link {
        case .wifi(let w):
            let level = w.rssi >= -67 ? 0 : w.rssi > NetworkCheck.weakSignal ? 1 : 2
            let channel = "ch \(w.channel)" + (w.band.isEmpty ? "" : " · \(w.band)")
            return ("wifi", min(1, max(0.05, Double(w.rssi + 90) / 30)), ["Strong", "Fair", "Weak"][level], "Wi-Fi signal", level,
                    "\(w.rssi) dBm on channel \(w.channel)" + (w.band.isEmpty ? "" : " (\(w.band))"), "\(w.rssi) dBm", channel)
        case .cable: return ("cable.connector", 1, "Cable", "connection", 0, "Connected by cable", "Cable", "connection")
        case .other: return ("point.3.connected.trianglepath.dotted", 1, "Other", "connection", 0, "Connected, but not by Wi-Fi or cable", "Other", "connection")
        case .none: return ("wifi.slash", 1, "None", "connection", 2, "Not connected to a network", "None", "connection")
        }
    }

    /// Download, upload and the wait when busy: dashes before a test, dashes moving while it runs, then the figures.
    @ViewBuilder func speedTiles(_ r: NetworkCheck.Result?) -> some View {
        let downLevel = r.map { $0.download < 5e6 ? 2 : $0.download < 15e6 ? 1 : 0 } ?? 0          // HD and 4K video
        let upLevel = r.map { $0.upload < 1e6 ? 2 : $0.upload < 3.8e6 ? 1 : 0 } ?? 0               // video calls
        let waitLevel = r.map { $0.rpm <= NetworkCheck.poorRPM ? 2 : $0.rpm < NetworkCheck.goodRPM ? 1 : 0 } ?? 0
        // plain labels under each figure, with its unit small beside it (Phil, 16 November 2026: "for a lay person that may
        // be technical jargon"); "Delay" rather than "latency", as it's what people notice
        tile("arrow.down", r.map { short($0.download) }, "Mbps", "Download", downLevel)
        tile("arrow.up", r.map { short($0.upload) }, "Mbps", "Upload", upLevel)
        tile("timer", r.map { NetworkCheck.grouped(NetworkCheck.delay($0)) }, "ms", "Delay", waitLevel)
    }

    func tile(_ symbol: String, _ value: String?, _ unit: String, _ label: String, _ level: Int) -> some View {
        tileFrame {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: symbol).font(.system(size: NetworkView.tileIcon, weight: .semibold))
                    .foregroundStyle(value == nil ? Ink.muted : NetworkView.color(level))
                if let value {
                    // the figure gives way before its unit does, so "Mbps" is never cut off
                    Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(unit).font(.caption2).foregroundStyle(Ink.muted).fixedSize().layoutPriority(1)
                } else if testing {
                    DashWave()
                } else {
                    Text("–").font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Ink.muted)
                }
            }
        } unit: { Text(label) }
    }

    /// The symbol on every speed and privacy tile, in points (Phil, 18 November 2026: "I think all the icons on those
    /// tiles need to be a little bigger", then "Let's do 14 points for the icon size").
    static let tileIcon: CGFloat = 14

    /// A tile's frame, the same size whatever it holds.
    func tileFrame<Top: View, Unit: View>(@ViewBuilder _ top: () -> Top, @ViewBuilder unit: () -> Unit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            top().frame(height: 24, alignment: .leading)
            unit().font(.caption2).foregroundStyle(Ink.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Start, Stop or Test again, always in the same place, with what pressing it means.
    @ViewBuilder var actionRow: some View {
        HStack(spacing: 10) {
            switch tester.phase {
            case .reading, .ready:
                Button("Start test") { tester.start() }.buttonStyle(RecommendedButton()).font(.callout)
                    .disabled(tester.phase == .reading)
                if tester.setup?.mayBeMetered == true {
                    Label(NetworkCheck.meteredNote, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                } else {
                    Text(NetworkCheck.dataNote).foregroundStyle(Ink.muted)
                }
            case .testing:
                Button("Stop") { tester.stop() }.buttonStyle(.bordered)
                Text("Stops the test. Or look elsewhere: it carries on, and its results wait here.").foregroundStyle(Ink.muted)
            case .done:
                Button("Test again") { note = nil; allFixes = false; tester.start() }.buttonStyle(.bordered)
                // when, beside the button and in bold, to read out on a call later; results are kept 30 minutes (Phil,
                // 19 November 2026: "The test time should be along the top or beside the button so it's extremely visible
                // to the user, not merged into explainer text")
                VStack(alignment: .leading, spacing: 2) {
                    if let f = tester.finished {
                        Text("Tested at \(NetworkView.stamp(f))").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    }
                    Text(NetworkCheck.dataNote).foregroundStyle(Ink.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 32)
    }

    /// Responsiveness on the draft's scale, Poor, Fair and Good, with a marker where this connection sits (none before a
    /// test, so the scale is there from the start).
    func meter(_ r: NetworkCheck.Result?) -> some View {
        // a log scale from 30 to 10,000 RPM, so the three bands each get room
        func x(_ rpm: Double) -> Double { min(1, max(0, (log10(rpm) - log10(30)) / (log10(10_000) - log10(30)))) }
        let poorEnd = x(Double(NetworkCheck.poorRPM)), fairEnd = x(Double(NetworkCheck.goodRPM))
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Capsule().fill(Color.orange.opacity(r == nil ? 0.2 : 0.55)).frame(width: w * poorEnd - 2)
                        Rectangle().fill(Color.yellow.opacity(r == nil ? 0.2 : 0.55)).frame(width: w * (fairEnd - poorEnd) - 2)
                        Capsule().fill(Color.green.opacity(r == nil ? 0.2 : 0.55))
                    }
                    .frame(height: 6)
                    if let r {
                        Circle().fill(Ink.text).frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Ink.card, lineWidth: 2))
                            .offset(x: w * x(Double(r.rpm)) - 5.5)
                    }
                }
            }
            .frame(height: 11)
            HStack {
                Text("Poor").frame(maxWidth: .infinity, alignment: .leading)
                Text("Fair").frame(maxWidth: .infinity, alignment: .center)
                Text("Good").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2).foregroundStyle(Ink.muted)
            Text("Responsiveness: " + (r.map { "\(NetworkCheck.grouped($0.rpm)) round trips a minute while busy" } ?? "after the test"))
                .font(.caption2).foregroundStyle(Ink.muted)
        }
    }

    /// Its own section, filled the same way as the speed: the VPN and who looks website names up are read on the Mac
    /// as the view opens; where websites see you comes with the test, which asks Cloudflare (Phil, 17 November 2026:
    /// "why not just include it as part of the single network test? It should be a separate privacy section though").
    /// Three tiles the size of the speed tiles, then one sentence on what it means; same size in every state.
    var privacy: some View {
        let s = tester.setup
        let vpn = s.map { NetworkCheck.vpnSaid($0.vpn) }
        let dns = s.map(NetworkCheck.dnsSaid)
        let seen = tester.seen.map { NetworkCheck.whereSaid($0, s?.vpn) }
        return VStack(alignment: .leading, spacing: 5) {
            Text("PRIVACY").font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(Ink.muted)
            HStack(spacing: 8) {
                privacyTile(vpn?.level == 0 ? "lock.shield.fill" : "lock.shield", vpn?.level ?? -1, vpn?.value, "VPN", waiting: s == nil)
                    .help(s.map { $0.vpn.map(NetworkCheck.vpnLine) ?? "No VPN is connected." } ?? "")
                privacyTile("text.magnifyingglass", -1, dns?.value, "Site lookup (DNS)", waiting: s == nil)
                    .help(s.map(NetworkCheck.dnsLine) ?? "")
                privacyTile("globe", seen?.level ?? -1, seen?.value, "Sites see you in", waiting: testing && seen == nil)
                    .help(seen?.detail ?? "")
            }
            Text(s.map { NetworkCheck.privacySentence($0, tester.seen) } ?? " ")
                .font(.caption).foregroundStyle(Ink.muted).lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A tile like the speed tiles: a symbol and a word on top, what it is under it; dashes while waiting.
    func privacyTile(_ symbol: String, _ level: Int, _ value: String?, _ label: String, waiting: Bool) -> some View {
        tileFrame {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: NetworkView.tileIcon, weight: .semibold))
                    .foregroundStyle(value == nil || level < 0 ? Ink.muted : NetworkView.color(level))
                if let value {
                    Text(value).font(.system(.callout, design: .rounded).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                } else if waiting {
                    DashWave()
                } else {
                    Text("–").font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(Ink.muted)
                }
            }
        } unit: { Text(label) }
    }

    func chip(_ words: String, _ symbol: String) -> some View {
        Label(words, systemImage: symbol).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }

    /// Everyday tasks, each with a tick, a "laggy" mark or a cross.
    func taskRow(_ r: NetworkCheck.Result?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("GOOD FOR").font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(Ink.muted)
            HStack(spacing: 6) {
                ForEach(NetworkCheck.tasks, id: \.name) { t in
                    let f = r.map { NetworkCheck.fit(t, $0) }
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: t.symbol).font(.system(size: 15)).frame(width: 26, height: 20)
                                .foregroundStyle(f == nil ? Ink.muted : Ink.text)
                            if let f {
                                Image(systemName: f == .fine ? "checkmark.circle.fill" : f == .laggy ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 10)).foregroundStyle(f == .fine ? Color.green : f == .laggy ? .yellow : .orange)
                                    .background(Circle().fill(Ink.card)).offset(x: 4, y: 3)
                            }
                        }
                        Text(t.name).font(.caption2).lineLimit(1)
                        Text(f.map { $0 == .fine ? "Fine" : $0 == .laggy ? "Laggy" : "Too slow" } ?? "–").font(.caption2.weight(.semibold))
                            .foregroundStyle(f == nil || f == .fine ? Ink.muted : Color.orange)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// The fixes, only when something is wrong, each as an option like a card's.
    @ViewBuilder func fixList(_ r: NetworkCheck.Result) -> some View {
        let fixes = tester.setup.map { NetworkCheck.fixes(r, $0) } ?? []
        if !fixes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // the most useful shown, the rest folded to one line with how many, as on a card (Phil, 18 November
                // 2026: "only have one expanded thing at a time"), so a bad result isn't a wall of options
                FixRow(fix: fixes[0], cooled: false, run: { act($0) }, runUntil: { act($0, until: $1) })
                if fixes.count > 1 {
                    GroupBar(doer: .you, count: fixes.count - 1, more: true, open: allFixes) {
                        withAnimation(.easeOut(duration: 0.15)) { allFixes.toggle() }
                    }
                    if allFixes {
                        ForEach(fixes.dropFirst()) { f in
                            FixRow(fix: f, cooled: false, run: { act($0) }, runUntil: { act($0, until: $1) })
                        }
                    }
                }
                if let note { Text(ui: note).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    func act(_ f: Fix, until: Date? = nil) {
        switch f.kind {
        case .pauseSync(let bundle, let name):
            guard let until else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: NSWorkspace.OpenConfiguration())
            watcher.addSyncPause(name: name, bundle: bundle, until: until)
            note = "Opened \(name). Pause it from its menu bar icon. We'll remind you to resume at \(Fmt.time(until))."
        case .openApp(let bundle, let steps):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: NSWorkspace.OpenConfiguration())
            note = "Opened \(((bundle as NSString).lastPathComponent as NSString).deletingPathExtension). \(steps)"
        case .openPage(_, let address):
            // System Settings opens its own pages by address; nothing changes until the person switches something there
            if let u = URL(string: address) { NSWorkspace.shared.open(u) }
            note = "Opened System Settings. \(f.consequence)"
        default:
            break       // guides open their steps under the option itself
        }
        watcher.log(NetworkCheck.logLine(f))         // the fix's id only: a title can name an app
    }

    /// The detail, one plain line each, folded away as on a card.
    func short(_ bits: Double) -> String {
        let m = bits / 1_000_000
        return m < 10 ? String(format: "%.1f", m) : NetworkCheck.grouped(Int(m.rounded()))
    }
}

/// Dashes moving across a tile while the test runs, in place of the figure it's measuring: light, and no images.
struct DashWave: View {
    var body: some View {
        // a step every 0.3 seconds: slow enough to read as calm (Phil, 16 November 2026: "slow down the animation on the numbers")
        TimelineView(.periodic(from: .now, by: 0.3)) { t in
            let step = Int(t.date.timeIntervalSinceReferenceDate / 0.3) % 4
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(Ink.muted.opacity(i == step ? 0.9 : 0.3)).frame(width: 7, height: 3)
                }
            }
        }
        .accessibilityLabel("Measuring")
    }
}
