import AppKit
import CoolHeadCore
import SwiftUI

/// "Test my network", one of the tools along the bottom of the panel, shown in the panel's middle. Opening it reads
/// what the Mac can say about its connection (no prompt, about a second); Apple's test runs only when Start test is
/// pressed, and stops if the view is closed.
@MainActor
final class NetworkTester: ObservableObject {
    static let shared = NetworkTester()

    enum Phase: Equatable { case reading, ready, testing(started: Date), done(NetworkCheck.Outcome) }

    @Published var shown = false
    @Published private(set) var phase = Phase.reading
    @Published private(set) var setup: NetworkCheck.Setup?
    private var work: Task<Void, Never>?

    /// Opens the view and reads the connection; nothing is sent.
    func open() {
        shown = true
        phase = .reading
        work?.cancel()
        work = Task {
            let s = await Task.detached { NetworkCheck.readSetup() }.value
            guard !Task.isCancelled else { return }
            setup = s
            phase = .ready
        }
    }

    /// Runs Apple's test. Who was using the network is read again first, since the test itself fills it.
    func start() {
        work?.cancel()
        phase = .testing(started: Date())
        work = Task {
            let s = await Task.detached { NetworkCheck.readSetup() }.value
            guard !Task.isCancelled else { return }
            setup = s
            let outcome = await NetworkCheck.run()
            guard !Task.isCancelled else { return }
            phase = .done(outcome)
        }
    }

    /// Stops a running test and goes back to the start.
    func stop() {
        work?.cancel()
        phase = setup == nil ? .reading : .ready
        if setup == nil { open() }
    }

    /// Closes the view; a test still running is stopped.
    func close() {
        work?.cancel()
        work = nil
        shown = false
        phase = .reading
    }

    /// For renders: show a given state without reading or testing.
    func show(_ phase: Phase, setup: NetworkCheck.Setup) {
        work?.cancel()
        self.setup = setup
        self.phase = phase
        shown = true
    }
}

struct NetworkView: View {
    @ObservedObject var tester: NetworkTester
    let watcher: Watcher
    @State private var nerdy = false
    @State private var note: String?
    @State private var allFixes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Test my network", systemImage: "network").font(.body.weight(.semibold))
                Spacer()
                Button { tester.close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            switch tester.phase {
            case .reading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking at your connection…").foregroundStyle(Ink.muted) }
                    .font(.callout)
            case .ready:
                if let s = tester.setup { linkRow(s); busyRow(s) }
                HStack(spacing: 10) {
                    Button("Start test") { tester.start() }.buttonStyle(RecommendedButton()).font(.callout)
                    Text(NetworkCheck.dataNote)
                        .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                if tester.setup?.mayBeMetered == true {
                    Label(NetworkCheck.meteredNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
                }
                nerdyStuff(nil)
            case .testing(let started):
                TimelineView(.periodic(from: started, by: 0.5)) { t in
                    let done = min(1, t.date.timeIntervalSince(started) / Double(NetworkCheck.testSeconds))
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: done).tint(.accentColor)
                        HStack {
                            Text("Testing… calls and downloads may slow for a moment.").font(.caption).foregroundStyle(Ink.muted)
                            Spacer()
                            Button("Stop") { tester.stop() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            case .done(let outcome):
                banner(NetworkCheck.verdict(outcome))
                if case .done(let r) = outcome {
                    tiles(r)
                    meter(r)
                    if let s = tester.setup { linkRow(s) }
                    taskRow(r)
                    fixList(r)
                }
                HStack {
                    Button("Test again") { note = nil; allFixes = false; tester.start() }.buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                }
                if case .done(let r) = outcome { nerdyStuff(r) } else { nerdyStuff(nil) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    // MARK: pieces

    static func color(_ level: Int) -> Color { [Color.green, .yellow, .orange][min(max(level, 0), 2)] }

    /// The answer in a few words, and what it means in plain words.
    func banner(_ v: NetworkCheck.Verdict) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: ["checkmark.circle.fill", "minus.circle.fill", "exclamationmark.triangle.fill"][min(v.level, 2)])
                .font(.title3).foregroundStyle(NetworkView.color(v.level))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.title).font(.callout.weight(.semibold))
                Text(v.meaning).font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Download, upload and the wait when busy, as three numbers.
    func tiles(_ r: NetworkCheck.Result) -> some View {
        let downLevel = r.download < 5e6 ? 2 : r.download < 15e6 ? 1 : 0          // HD and 4K video
        let upLevel = r.upload < 1e6 ? 2 : r.upload < 3.8e6 ? 1 : 0                // video calls
        let waitLevel = r.rpm <= NetworkCheck.poorRPM ? 2 : r.rpm < NetworkCheck.goodRPM ? 1 : 0
        return HStack(spacing: 8) {
            tile("arrow.down", short(r.download), "Mbps down", downLevel)
            tile("arrow.up", short(r.upload), "Mbps up", upLevel)
            tile("timer", NetworkCheck.grouped(NetworkCheck.delay(r)), "ms wait when busy", waitLevel)
        }
    }

    func tile(_ symbol: String, _ value: String, _ unit: String, _ level: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(NetworkView.color(level))
                Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            Text(unit).font(.caption2).foregroundStyle(Ink.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Responsiveness on the draft's scale, Poor, Fair and Good, with a marker where this connection sits.
    func meter(_ r: NetworkCheck.Result) -> some View {
        // a log scale from 30 to 10,000 RPM, so the three bands each get room
        func x(_ rpm: Double) -> Double { min(1, max(0, (log10(rpm) - log10(30)) / (log10(10_000) - log10(30)))) }
        let poorEnd = x(Double(NetworkCheck.poorRPM)), fairEnd = x(Double(NetworkCheck.goodRPM))
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Capsule().fill(Color.orange.opacity(0.55)).frame(width: w * poorEnd - 2)
                        Rectangle().fill(Color.yellow.opacity(0.55)).frame(width: w * (fairEnd - poorEnd) - 2)
                        Capsule().fill(Color.green.opacity(0.55))
                    }
                    .frame(height: 6)
                    Circle().fill(Ink.text).frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Ink.card, lineWidth: 2))
                        .offset(x: w * x(Double(r.rpm)) - 5.5)
                }
            }
            .frame(height: 11)
            HStack {
                Text("Poor").frame(maxWidth: .infinity, alignment: .leading)
                Text("Fair").frame(maxWidth: .infinity, alignment: .center)
                Text("Good").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2).foregroundStyle(Ink.muted)
            Text("Responsiveness: \(NetworkCheck.grouped(r.rpm)) round trips a minute while busy").font(.caption2).foregroundStyle(Ink.muted)
        }
    }

    /// How the Mac is connected, at a glance.
    @ViewBuilder func linkRow(_ s: NetworkCheck.Setup) -> some View {
        HStack(spacing: 8) {
            switch s.link {
            case .wifi(let w):
                let strength = min(1, max(0.05, Double(w.rssi + 90) / 40))
                Image(systemName: "wifi", variableValue: strength)
                    .foregroundStyle(w.rssi <= NetworkCheck.weakSignal ? Color.orange : Ink.text)
                Text("Wi-Fi \(w.rssi <= NetworkCheck.weakSignal ? "signal weak" : "signal fine")").font(.callout)
                Spacer()
                Text("\(w.rssi) dBm · ch \(w.channel)\(w.band.isEmpty ? "" : " · \(w.band)")").font(.caption).foregroundStyle(Ink.muted).monospacedDigit()
            case .cable:
                Image(systemName: "cable.connector"); Text("Connected by cable").font(.callout); Spacer()
            case .other:
                Image(systemName: "point.3.connected.trianglepath.dotted"); Text("Connected another way").font(.callout); Spacer()
            case .none:
                Image(systemName: "wifi.slash").foregroundStyle(.orange); Text("Not connected").font(.callout); Spacer()
            }
            if s.vpn { chip("VPN", "lock.fill") }
            if s.proxy || s.autoProxy { chip("Proxy", "arrow.triangle.branch") }
        }
    }

    func chip(_ words: String, _ symbol: String) -> some View {
        Label(words, systemImage: symbol).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }

    /// What's using the network now, if anything much.
    @ViewBuilder func busyRow(_ s: NetworkCheck.Setup) -> some View {
        let busy = s.talkers.filter { $0.bytesPerSecond >= NetworkCheck.talkerFloor }.prefix(3)
        if !busy.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.up.arrow.down").font(.caption).foregroundStyle(Ink.muted)
                Text(busy.map { "\($0.name) \(NetworkCheck.rate($0.bytesPerSecond).replacingOccurrences(of: " a second", with: "/s"))" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Everyday tasks, each with a tick, a "laggy" mark or a cross.
    func taskRow(_ r: NetworkCheck.Result) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("GOOD FOR").font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(Ink.muted)
            HStack(spacing: 6) {
                ForEach(NetworkCheck.tasks, id: \.name) { t in
                    let f = NetworkCheck.fit(t, r)
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: t.symbol).font(.system(size: 15)).frame(width: 26, height: 20)
                            Image(systemName: f == .fine ? "checkmark.circle.fill" : f == .laggy ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 10)).foregroundStyle(f == .fine ? Color.green : f == .laggy ? .yellow : .orange)
                                .background(Circle().fill(Ink.card)).offset(x: 4, y: 3)
                        }
                        Text(t.name).font(.caption2).lineLimit(1)
                        Text(f == .fine ? "Fine" : f == .laggy ? "Laggy" : "Too slow").font(.caption2.weight(.semibold))
                            .foregroundStyle(f == .fine ? Ink.muted : Color.orange)
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
                GroupHeading(doer: .you)
                // the three most useful; the rest on request, so a bad result isn't a wall of options
                ForEach(allFixes ? fixes : Array(fixes.prefix(3))) { f in
                    FixRow(fix: f, cooled: false, run: { act($0) }, runUntil: { act($0, until: $1) })
                }
                if fixes.count > 3 {
                    Button { withAnimation(.easeOut(duration: 0.15)) { allFixes.toggle() } } label: {
                        Label(allFixes ? "Fewer options" : "More options (\(fixes.count - 3))", systemImage: allFixes ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                if let note { Text(note).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
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
    @ViewBuilder func nerdyStuff(_ r: NetworkCheck.Result?) -> some View {
        if let s = tester.setup {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).rotationEffect(.degrees(nerdy ? 90 : 0))
                    Text("Nerdy stuff (detailed info)").font(.caption)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { nerdy.toggle() } }
                .accessibilityAddTraits(.isButton)
                if nerdy {
                    ForEach(NetworkCheck.lines(r, s), id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(Ink.muted)
        }
    }

    func short(_ bits: Double) -> String {
        let m = bits / 1_000_000
        return m < 10 ? String(format: "%.1f", m) : NetworkCheck.grouped(Int(m.rounded()))
    }
}
