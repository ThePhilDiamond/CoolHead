import Darwin
import Foundation
import CoolHeadCore

let usage = """
coolhead: explains what is keeping this Mac busy, hot or awake.

  coolhead now              the Mac's state and a card for each busy process
  coolhead why <pid|name>   the card and the evidence for one process
  coolhead case <pid|name>  what "Share this case" would show for a process (nothing is sent)
  coolhead memory           who is using the memory, counted by app, and what could be done
  coolhead selftest         checks every recorded example gives the card it should
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

let argv = CommandLine.arguments.dropFirst()
switch argv.first {
case "now":
    let state = MacState.read()
    printState(state)
    print("")
    for (pid, cores) in busiest(limit: 8) where cores >= 0.25 {
        guard let e = Evidence.gather(pid: pid, interval: 0.5) else { continue }
        printCard(Card.make(e, now: testNow, warm: state.thermal != "nominal"))
        print("")
    }
case "why":
    guard let target = argv.dropFirst().first else { print(usage); exit(64) }
    guard let p = find(target), let e = Evidence.gather(pid: p) else { print("coolhead: no process matches \(target)"); exit(1) }
    printCard(Card.make(e, now: testNow, warm: MacState.read().thermal != "nominal"))
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
case "selftest":
    let results = Fixture.runAll()
    for (id, ok, note) in results { print("\(ok ? "pass" : "FAIL")  \(id)  \(note)") }
    let failed = results.filter { !$0.1 }.count
    print("\(results.count - failed) of \(results.count) passed")
    exit(failed == 0 ? 0 : 1)
default:
    print(usage)
}
