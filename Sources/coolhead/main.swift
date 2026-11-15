import Darwin
import Foundation
import CoolHeadCore

let usage = """
coolhead: explains what is keeping this Mac busy, hot or awake.

  coolhead now              the Mac's state and a card for each busy process
  coolhead why <pid|name>   the card and the evidence for one process
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
    row("command", e.args.joined(separator: " "))
    row("folder", e.cwd)
    row("started", e.start.map { "\(Fmt.time($0)), \(Fmt.duration(Date().timeIntervalSince($0))) ago" })
    row("started by", e.startedBy)
    row("launched as", e.launchCommand)
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
    row("saves as it goes", e.savesAsItGoes ? "yes" : "no sign of it")
    if let p = e.progress {
        row("progress", p.line)
        row("  from", "\(p.file), written \(Fmt.time(p.lineTime))")
    }
}

/// For testing: pretend this many minutes have passed (COOLHEAD_NOW_PLUS_MINUTES).
let testNow = Date().addingTimeInterval(60 * (Double(ProcessInfo.processInfo.environment["COOLHEAD_NOW_PLUS_MINUTES"] ?? "") ?? 0))

func printCard(_ c: Card) {
    print("\(c.headline)\n→ \(c.action)" + (c.caution.map { "\n  \($0)" } ?? ""))
}

let argv = CommandLine.arguments.dropFirst()
switch argv.first {
case "now":
    printState(MacState.read())
    print("")
    for (pid, cores) in busiest(limit: 8) where cores >= 0.25 {
        guard let e = Evidence.gather(pid: pid, interval: 0.5) else { continue }
        printCard(Card.make(e, now: testNow))
        print("")
    }
case "why":
    guard let target = argv.dropFirst().first else { print(usage); exit(64) }
    var pid: pid_t? = pid_t(target)
    if pid == nil {
        let want = target.lowercased()
        pid = busiest(limit: 2000, interval: 0.5).first { p, _ in
            (Proc.bsd(p)?.name.lowercased().contains(want) ?? false)
                || Proc.args(p).joined(separator: " ").lowercased().contains(want)
        }?.0
    }
    guard let p = pid, let e = Evidence.gather(pid: p) else { print("coolhead: no process matches \(target)"); exit(1) }
    printCard(Card.make(e, now: testNow))
    print("\nEvidence")
    printEvidence(e)
    print("\nThe Mac")
    printState(MacState.read())
default:
    print(usage)
}
