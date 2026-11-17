import Darwin
import Foundation
import CoolHeadCore

// the selftest's throwaway app (a copy of this program in a bundle of its own): it records how it was opened, and
// waits to be asked to quit, so the selftest can restart it the way Cool Head restarts a browser
if BrowserRestart.isTestApp(Bundle.main.bundleIdentifier) { BrowserRestart.runTestApp() }

let usage = """
coolhead: explains what is keeping this Mac busy, hot or awake.

  coolhead now                 the Mac's state and a card for each busy process
  coolhead why <name or PID>   the card and the evidence for one process
  coolhead case <name or PID>  what "Share this case" would show for a process (nothing is sent)
  coolhead memory              who is using the memory, counted by app, and what could be done
  coolhead hangs               what's paused, stuck waiting on a drive, or not responding right now
  coolhead hardware            the drive, battery, crash restarts and ports, checked without a password
  coolhead network             what the Mac can say about its connection; add --test to run Apple's network test,
                               which also asks Cloudflare where websites see you (or --where for that alone)
  coolhead history             what used the most energy and why the Mac woke, from macOS's power log (about a week)
  coolhead selftest            checks every recorded example gives the card it should
  coolhead wording             every card's text, from the recorded examples, to read the wording in one place
  coolhead ranking [--write]   which card and option every sample gets; --write records it for the selftest
  coolhead cards [--json|--why] every kind of card about a busy process: its rule and samples; --why reviews why lines

<name or PID>: the process's name as Activity Monitor shows it, or its PID (the number in Activity Monitor's PID
column), without the angle brackets: coolhead why mds_stores. Part of a name is enough; when several processes match,
the busiest is used. Put a name with spaces in quotes: coolhead why "Google Chrome Helper".
"""

func busiest(limit: Int, interval: TimeInterval = 1.0) -> [(pid_t, Double)] {
    let pids = Proc.allPIDs()
    var first: [pid_t: Double] = [:]
    for p in pids { if let u = Proc.usage(p) { first[p] = u.cpuSeconds } }
    let t = Date()
    Thread.sleep(forTimeInterval: interval)
    let dt = Date().timeIntervalSince(t)
    var out: [(pid_t, Double)] = []
    for (p, a) in first { if let u = Proc.usage(p) { out.append((p, max(0, u.cpuSeconds - a) / dt)) } }
    return Array(out.sorted { $0.1 > $1.1 }.prefix(limit))
}

func printState(_ s: MacState) {
    var parts = ["Heat: \(s.thermal)", "memory pressure: \(s.memoryPressure)"]
    if s.swapTotalMB > 0 { parts.append(String(format: "swap %.1f of %.1f GB", s.swapUsedMB / 1024, s.swapTotalMB / 1024)) }
    print(parts.joined(separator: " · "))
    var b: [String] = []
    if let pct = s.batteryPercent { b.append("Battery \(pct)%" + (s.charging ? ", charging" : s.onPower ? ", on power" : "")) }
    if let w = s.macWatts { b.append(String(format: "Mac using %.0f W", w)) }
    if let w = s.batteryWatts, s.charging, w > 0.5 { b.append(String(format: "battery taking %.0f W", w)) }
    if let w = s.adapterWatts { b.append("\(w) W charger") }
    if let h = s.healthPercent, let c = s.cycles { b.append("battery holds \(h)% of its original charge after \(c) cycles") }
    if !b.isEmpty { print(b.joined(separator: " · ")) }
}

func printEvidence(_ e: Evidence) {
    func row(_ k: String, _ v: String?) { if let v, !v.isEmpty { print("  \(k.padding(toLength: 12, withPad: " ", startingAt: 0)) \(v)") } }
    row("process", "\(e.name) (pid \(e.pid))\(e.mine ? "" : ", another user's or the system's")")
    row("command", Redact.args(e.args).joined(separator: " "))
    row("folder", e.cwd)
    row("started", e.start.map { "\(Fmt.time($0)), \(Fmt.duration(Date().timeIntervalSince($0))) ago" })
    row("started by", e.startedBy)
    row("launched as", e.launchCommand.map(Redact.text))
    row("parents", e.ancestors.map { "\($0.name) (\($0.pid))" }.joined(separator: " ← "))
    row("CPU now", Fmt.cores(e.coresNow))
    row("CPU average", Fmt.cores(e.coresAverage) + " since it started")
    row("fast cores", e.performanceShare.map { "\(Fmt.percent($0)) of its time on the performance cores" })
    row("graphics", e.gpuShare.map { "\(Fmt.share($0)) of the graphics chip" })
    row("memory", Fmt.bytes(e.memoryBytes))
    for w in e.writing { row("writing", w) }
    for l in e.locks { row("lock", l.path + (l.note.map { "  (says: \($0))" } ?? "")) }
    row("state", Health.assess(e, now: testNow).rawValue)
    row("work began", e.workStart.map { Fmt.time($0) })
    row("last output", e.lastOutput.map { Fmt.time($0) })
    row("last line", e.lastLine)
    if let p = e.progress {
        row("progress", p.line)
        row("  from", "\(p.file), written \(Fmt.time(p.lineTime))")
    }
}

/// For testing: pretend this many minutes have passed (COOLHEAD_NOW_PLUS_MINUTES).
let testNow = Date().addingTimeInterval(60 * (Double(ProcessInfo.processInfo.environment["COOLHEAD_NOW_PLUS_MINUTES"] ?? "") ?? 0))

func printCard(_ c: Card) {
    print(c.headline)
    print("  \(c.explanation)")
    for f in c.fixes { print("  \(f.recommended ? "→" : "·") \(f.title)" + (f.consequence.isEmpty ? "" : ": \(f.consequence)")) }
}

/// A process by number, or by name: of the processes whose name or command contains it, the busiest.
func find(_ target: String) -> pid_t? {
    if let p = pid_t(target) { return p }
    let want = target.lowercased()
    // leave out coolhead itself and the shell that ran it (its command line contains the name searched for)
    var mine: Set<pid_t> = [getpid()]
    var p = getppid()
    while p > 1, let b = Proc.bsd(p) { mine.insert(p); p = b.ppid }
    let all = Proc.allPIDs().filter { !mine.contains($0) }
    // a match on the process name wins (for other users' processes, the name comes from the path); only if none,
    // look in command lines
    func name(_ p: pid_t) -> String? { Proc.bsd(p)?.name ?? Proc.path(p).map { ($0 as NSString).lastPathComponent } }
    var matches = all.filter { name($0)?.lowercased().contains(want) ?? false }
    if matches.isEmpty { matches = all.filter { Proc.args($0).joined(separator: " ").lowercased().contains(want) } }
    let busy = Dictionary(busiest(limit: 5000, interval: 0.5).map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    return matches.max { (busy[$0] ?? 0) < (busy[$1] ?? 0) }
}

/// For one of macOS's own processes, a one-off look (no record kept): its priority and a recent update.
func oneOff(_ e: Evidence, _ mac: MacState) -> BackgroundWork.Reading? {
    guard e.script == nil, let p = e.path, CaseReport.isMacOS(p) else { return nil }
    return BackgroundWork.read(e, busySince: nil, efficiencyCores: mac.efficiencyCores, track: false)
}

let argv = CommandLine.arguments.dropFirst()
switch argv.first {
case "now":
    let state = MacState.read()
    printState(state)
    print("")
    // busy on the CPU, or on the graphics chip (measured over the same second)
    let g1 = GPU.times(), t1 = Date()
    let cpu = busiest(limit: 8).filter { $0.1 >= 0.25 }.map(\.0)
    let g2 = GPU.times(), seconds = Date().timeIntervalSince(t1)
    let drawing = g2.filter { GPU.share(from: g1[$0.key] ?? $0.value, to: $0.value, seconds: seconds) >= GPU.quietShare }.map(\.key)
    for pid in cpu + drawing.filter({ !cpu.contains($0) }) {
        guard let e = Evidence.gather(pid: pid, interval: 0.5) else { continue }
        printCard(Card.make(e, now: testNow, warm: state.thermal != "nominal", disguise: Disguise.find(e), background: oneOff(e, state),
                            apps: AppBuild.facts(e, isWindowServer: e.name == "WindowServer")))
        print("")
    }
case "why":
    guard let target = argv.dropFirst().first else { print(usage); exit(64) }
    guard let p = find(target), let e = Evidence.gather(pid: p) else { print("coolhead: no process matches \(target)"); exit(1) }
    let mac = MacState.read()
    printCard(Card.make(e, now: testNow, warm: mac.thermal != "nominal", disguise: Disguise.find(e), background: oneOff(e, mac),
                        apps: AppBuild.facts(e, isWindowServer: e.name == "WindowServer")))
    print("\nEvidence")
    printEvidence(e)
    print("\nThe Mac")
    printState(MacState.read())
case "case":
    guard let target = argv.dropFirst().first else { print(usage); exit(64) }
    guard let p = find(target), let e = Evidence.gather(pid: p) else { print("coolhead: no process matches \(target)"); exit(1) }
    let c = Card.make(e)
    print(CaseReport.title(e, card: c))
    print("")
    print(CaseReport.make(e, card: c, mac: MacState.read(), busySince: nil))
case "memory":
    let s = MacState.read()
    var groups = MemoryAdvice.merge(Proc.allPIDs().compactMap { p in
        MemoryAdvice.group(pid: p, path: Proc.path(p), args: Proc.args(p), footprint: Proc.usage(p)?.footprint ?? 0)
    })
    for i in groups.indices.prefix(3) where groups[i].kind == .job {
        if let p = groups[i].pid { groups[i].evidence = Evidence.gather(pid: p, interval: 0.5) }
    }
    print("Memory pressure: \(s.memoryPressure)" + String(format: " · swap %.1f of %.1f GB", s.swapUsedMB / 1024, s.swapTotalMB / 1024))
    for g in groups.prefix(6) {
        print("  \(Fmt.bytes(g.bytes).padding(toLength: 8, withPad: " ", startingAt: 0)) \(MemoryAdvice.label(g))" + (g.count > 1 ? " (\(g.count) processes)" : ""))
    }
    print("")
    printCard(MemoryAdvice.card(groups, mac: s))
case "hangs":
    // what's stuck right now: paused by something other than Cool Head, waiting on a drive, or Not Responding
    var found: [(pid_t, Hang.Kind)] = Proc.psTable().compactMap { pid, row in
        pid > 1 ? Hang.kind(psState: row.state).map { (pid, $0) } : nil
    }
    found += Hang.notResponding().map { ($0, Hang.Kind.notResponding) }
    if found.isEmpty { print("Nothing is paused, waiting on a drive, or not responding" + (Hang.canCheckResponding ? "." : " (this Mac can't say which apps are Not Responding).")) }
    let pids = Proc.allPIDs()
    for (pid, kind) in found.sorted(by: { $0.0 < $1.0 }) {
        guard let e = Evidence.gather(pid: pid, interval: 0.3, readFiles: kind != .diskWait) else { continue }
        let waiting = Proc.children(of: pid, among: pids).compactMap { Proc.bsd($0)?.name }
        print("[\(kind.rawValue)] pid \(pid)")
        printCard(Hang.card(kind, e, stuckFor: 0, waiting: waiting, volumes: kind == .diskWait ? Hang.volumes(pid) : [],
                            terminal: Hang.terminalApp(e, pid: pid)))
        print("")
    }
case "hardware":
    let report = HardwareReport.read(now: testNow)
    for line in report.summary() { print(line) }
    for c in report.cards(now: testNow) { print(""); printCard(c.card) }
case "network":
    // Apple's test fills the connection and uses data, so it runs only when asked for
    let setup = NetworkCheck.readSetup()
    var result: NetworkCheck.Result?
    if argv.dropFirst().first == "--test" {
        print("Testing for up to \(NetworkCheck.testSeconds) seconds…")
        let outcome = await NetworkCheck.run()
        let v = NetworkCheck.verdict(outcome)
        print("\(v.title). \(v.meaning)")
        if case .done(let r) = outcome {
            result = r
            print("  " + NetworkCheck.tasks.map { "\($0.name): \(["fine", "laggy", "too slow"][[.fine, .laggy, .tooSlow].firstIndex(of: NetworkCheck.fit($0, r))!])" }.joined(separator: " · "))
            for f in NetworkCheck.fixes(r, setup) { print("  \(f.recommended ? "→" : "·") \(f.title): \(f.consequence)") }
        }
    }
    for line in NetworkCheck.lines(result, setup) { print("  \(line)") }
    // asks Cloudflare, so only when asked for; prints the country, never the address
    if argv.dropFirst().contains("--where") || argv.dropFirst().first == "--test" {
        let w = NetworkCheck.whereSaid(NetworkCheck.whereSeen(setup), setup.vpn)
        print("  Websites see you in: \(w.value). \(w.detail)")
    }
case "history":
    guard let h = PowerHistory.read() else { print("No history: this Mac's power log couldn't be read."); exit(0) }
    print(h.text)
case "wording":
    for (id, c) in Wording.samples() { print("[\(id)]"); print(Wording.text(c)) }
case "ranking":
    // every sample card's winner and options (see Ranking.swift); --write records them in GoldenRanking.swift
    let lines = Ranking.lines()
    if argv.dropFirst().first == "--write" {
        let explained = Ranking.explanationLines()
        do {
            try Ranking.source(lines).write(to: Ranking.file, atomically: true, encoding: .utf8)
            try Ranking.explanationsSource(explained).write(to: Ranking.explanationsFile, atomically: true, encoding: .utf8)
        } catch { print("coolhead: couldn't write the golden files: \(error.localizedDescription)"); exit(1) }
        print("Wrote \(lines.count) lines to \(Ranking.file.path) and \(explained.count) to \(Ranking.explanationsFile.path)")
    } else {
        for l in lines { print(l) }
    }
case "cards":
    if argv.dropFirst().first == "--why" {
        // every situation the samples and checks give Card.make, and the made-up overlaps, each varied in warmth,
        // battery, a game and the front app: each pattern of sentences in the "why" line, with examples
        var seen: [Situation] = []
        Card.observer = { seen.append($0) }
        _ = Wording.samples()
        _ = Fixture.runAll()
        Card.observer = nil
        seen += Fixture.overlaps().map(\.1)
        var patterns: [String: [String]] = [:]
        var missing: [String] = []
        var count = 0
        for s in seen {
            for warm in [false, true] { for battery in [nil, 30] as [Int?] { for game in [nil, "Lumen"] as [String?] {
                for front in [nil, s.e.appBundle] as [String?] {
                    let v = Situation(s.e, now: s.now, busySince: s.busySince, warm: warm, gameRunning: game, frontApp: front, battery: battery,
                                      syncFeed: s.syncFeed, agent: s.agent, backupFeed: s.backupFeed, disguise: s.disguise, background: s.background, apps: s.apps)
                    let (card, choice) = Ranker.choose(v)
                    count += 1
                    let line = "[\(choice.winner)] \(card.headline) | " + (choice.line ?? "(nothing to explain)")
                    for m in Decision.missing(card, id: choice.winner) where !missing.contains(m) { missing.append(m) }
                    if !(patterns[choice.pattern] ?? []).contains(line) { patterns[choice.pattern, default: []].append(line) }
                }
            } } }
        }
        print("\(seen.count) situations, \(count) variations, \(patterns.count) patterns\n")
        if !missing.isEmpty { print("## Missing facts (\(missing.count))"); for m in missing.sorted() { print("- " + m) }; print("") }
        for (p, lines) in patterns.sorted(by: { $0.key < $1.key }) {
            print("## \(p) (\(lines.count) distinct)")
            for l in lines { print("- " + l) }
            print("")
        }
    } else if argv.dropFirst().first == "--json" {
        let data = try JSONSerialization.data(withJSONObject: Ranker.list(), options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        for line in Ranker.listText() { print(line) }
    }
case "selftest":
    let results = Fixture.runAll()
    for (id, ok, note) in results { print("\(ok ? "pass" : "FAIL")  \(id)  \(note)") }
    let failed = results.filter { !$0.1 }.count
    print("\(results.count - failed) of \(results.count) passed")
    exit(failed == 0 ? 0 : 1)
default:
    print(usage)
}
