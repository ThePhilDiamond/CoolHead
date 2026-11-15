import Foundation

/// Whether a busy process is doing its job, and how we know.
public enum JobState: String {
    case working      // progress advancing, or output still being written
    case waiting      // queued behind another job
    case stalled      // no progress for a long time: the only state where stopping is offered
    case unknown      // busy for a long time, with no sign either way
    case starting     // busy, but only just started
    case quiet        // not busy
}

public enum Health {
    /// Minutes without progress before a job counts as stalled (COOLHEAD_STALL_MINUTES overrides it, for testing).
    public static var stallMinutes: Double {
        Double(ProcessInfo.processInfo.environment["COOLHEAD_STALL_MINUTES"] ?? "") ?? 30
    }

    /// `busySince`: when the watcher first saw it busy; without it, the process's start time is used.
    public static func assess(_ e: Evidence, now: Date = Date(), busySince: Date? = nil) -> JobState {
        let busy = e.coresNow >= 0.25
        let ran = now.timeIntervalSince(busySince ?? e.start ?? now)
        if let l = e.lastLine?.lowercased(), l.contains("waiting"), e.coresNow < 0.1 { return .waiting }
        if let p = e.progress {
            // stalled: quiet for longer than the limit and than three of its own usual gaps between progress lines
            let limit = max(stallMinutes, 3 * (p.typicalGapMinutes ?? 0))
            return now.timeIntervalSince(p.lineTime) > limit * 60 ? .stalled : .working
        }
        if e.bytesWrittenDuringSample > 0 || (e.lastOutput.map { now.timeIntervalSince($0) < 600 } ?? false) {
            return busy || ran < 600 ? .working : .quiet
        }
        if busy && ran < 20 * 60 { return .starting }
        return busy ? .unknown : .quiet
    }
}

/// One thing the user can do about a card, with what it would cause.
public struct Fix: Identifiable {
    public enum Kind: Equatable {
        case wait(Date)          // hide the card until then; it comes back if the cause is still there
        case stop                // SIGTERM, after asking; only the user's own processes
        case cooler              // background priority: slower CPU and disk access, less heat
        case lookUp(String)      // a web search for this process name only
        case quitApp(String)     // a normal quit, so the app can ask to save
        case info                // advice with nothing to press
    }
    public let id: String
    public let title: String
    public let consequence: String
    public let kind: Kind
    public var recommended = false
}

/// What the user sees: one sentence saying what it is and whether it is fine; behind "Explore fixes", a short
/// explanation of how we know, and the options, each with its consequence, one of them recommended.
public struct Card {
    public let state: JobState
    public let headline: String
    public let explanation: String
    public let fixes: [Fix]

    public init(state: JobState, headline: String, explanation: String, fixes: [Fix]) {
        self.state = state; self.headline = headline; self.explanation = explanation
        // recommended first
        self.fixes = fixes.filter(\.recommended) + fixes.filter { !$0.recommended }
    }

    public var recommended: Fix? { fixes.first { $0.recommended } }

    /// Who the card is about, in plain words.
    public static func subject(_ e: Evidence) -> String {
        // a script names the job better than its runtime (Homebrew's Python is itself an app bundle)
        if e.script != nil {
            if let p = e.project { return "Your \(p) job \(e.task)" }
            return "Your script \(e.task)"
        }
        if let app = e.app { return app }
        return e.name
    }

    static func wait(until: Date?, now: Date, recommended: Bool) -> Fix {
        if let u = until, u > now.addingTimeInterval(120) {
            return Fix(id: "wait", title: "Do nothing; check back at \(Fmt.time(u))", consequence: "It should be done by then. The card returns if it isn't.",
                       kind: .wait(u), recommended: recommended)
        }
        return Fix(id: "wait", title: "Do nothing; check back in 30 minutes", consequence: "Nothing changes. Cool Head keeps watching, and the card returns if it is still busy.",
                   kind: .wait(now.addingTimeInterval(1800)), recommended: recommended)
    }

    static func lookUp(_ name: String, recommended: Bool) -> Fix {
        Fix(id: "lookup", title: "Look it up", consequence: "Opens a web search for \u{201C}\(name)\u{201D} in your browser. Nothing else is sent.",
            kind: .lookUp(name), recommended: recommended)
    }

    public static func make(_ e: Evidence, now: Date = Date(), busySince: Date? = nil, warm: Bool = false) -> Card {
        let who = subject(e)
        let since = busySince ?? e.start ?? now
        let busyFor = now.timeIntervalSince(since)
        let state = Health.assess(e, now: now, busySince: busySince)
        let started = "Started at \(Fmt.time(e.start ?? now)) by \(e.startedBy)."
        let atStake = now.timeIntervalSince(e.workStart ?? e.start ?? now)
        let output = e.writing.first { !Evidence.isLog($0) }.map { ($0 as NSString).lastPathComponent }

        // what stopping would cost, in plain words
        func stopConsequence() -> String {
            if state == .stalled, let p = e.progress {
                return "It has done nothing new since \(Fmt.time(p.lineTime)), so nothing after that is lost. Run it again afterwards."
            }
            var parts: [String] = []
            if atStake >= 10 * 60 {
                parts.append(e.savesAsItGoes ? "It saves as it goes, so you would lose only the latest part."
                                             : "You would lose about \(Fmt.duration(atStake)) of work, and have to run it again from the start.")
            } else {
                parts.append("It started recently, so little work is lost; you would have to run it again.")
            }
            if let o = output { parts.append("\(o) may be left half-written.") }
            return parts.joined(separator: " ")
        }
        let stop: Fix? = e.mine ? Fix(id: "stop", title: "Stop it", consequence: stopConsequence(), kind: .stop, recommended: state == .stalled) : nil
        let cooler: Fix? = e.mine && e.coresNow >= 0.5
            ? Fix(id: "cooler", title: "Run it cooler",
                  consequence: "Moves it to the low-power cores and slows its disk use. It takes longer, but the Mac stays cooler and more responsive. You can undo it.",
                  kind: .cooler, recommended: false)
            : nil

        // macOS's own processes: what it is doing, and whether this has gone on longer than usual
        if let k = Pattern.match(name: e.name, path: e.path), e.progress == nil {
            let long = busyFor > k.usualHours * 3600 && busyFor >= 20 * 60
            let explanation = "\(k.doing). That's normal \(k.normal)"
                + (k.usualHours < 100 ? "; it usually takes under \(Fmt.duration(k.usualHours * 3600))." : ".")
                + " It has been busy for \(Fmt.duration(busyFor))."
            var fixes: [Fix] = []
            if long {
                if k.whenLong == "Look it up" { fixes.append(lookUp(e.name, recommended: true)) }
                else { fixes.append(Fix(id: "advice", title: k.whenLong, consequence: k.risk ?? "", kind: .info, recommended: true)) }
                fixes.append(wait(until: nil, now: now, recommended: false))
            } else {
                fixes.append(wait(until: nil, now: now, recommended: true))
            }
            if let app = e.quittableApp, k.risk != nil, k.whenLong.hasPrefix("Quit") {
                fixes.append(Fix(id: "quit", title: "Quit \(app)", consequence: k.risk!, kind: .quitApp(app)))
            }
            if !e.mine { fixes.append(Fix(id: "nostop", title: "Stopping it isn't offered", consequence: "It belongs to macOS, which would start it again.", kind: .info)) }
            let head = e.coresNow < 0.25 ? "\(k.doing). It is quiet now."
                : long ? "\(k.doing), and has been at it for \(Fmt.duration(busyFor)), which is longer than usual."
                : "\(k.doing). That's normal \(k.normal)" + (k.endsOnItsOwn ? ", and it finishes on its own." : ".")
            return Card(state: e.coresNow < 0.25 ? .quiet : long ? .unknown : .working, headline: head, explanation: explanation, fixes: fixes)
        }

        // web pages: the busy process is a tab or extension, and only the browser knows which
        if let app = e.app, e.name.contains("Renderer") || e.name.contains("Web Content") || e.name.contains("(Plugin)") {
            let tm = app.contains("Safari") ? "Window ▸ Activity" : "Window ▸ Task Manager"
            return Card(state: e.coresNow < 0.25 ? .quiet : busyFor > 20 * 60 ? .unknown : .starting,
                        headline: "A tab or extension in \(app) has used about \(Fmt.cores(e.coresNow)) for \(Fmt.duration(busyFor)).",
                        explanation: "Each tab and extension runs as its own process. macOS can't see which one this is, but \(app) can.",
                        fixes: [Fix(id: "find", title: "Find it: in \(app), choose \(tm)", consequence: "Sort by CPU, then close just that tab or extension.", kind: .info, recommended: true),
                                wait(until: nil, now: now, recommended: false),
                                e.quittableApp.map { Fix(id: "quit", title: "Quit \($0)", consequence: "Closes every tab and window; most browsers can reopen them.", kind: .quitApp($0)) }].compactMap { $0 })
        }

        switch state {
        case .working:
            if let p = e.progress {
                var head = "\(who) is " + (p.fraction.map { "\(Fmt.percent($0)) done." } ?? "making progress.")
                if let fin = p.finish { head += fin > now ? " Done around \(Fmt.time(fin))." : " It should finish any minute." }
                let expl = "Its log says \u{201C}\(p.line)\u{201D} (written \(Fmt.time(p.lineTime))). \(started)"
                return Card(state: state, headline: head, explanation: expl,
                            fixes: [wait(until: p.finish, now: now, recommended: !warm || cooler == nil), cooler.map { var c = $0; c.recommended = warm; return c }, stop].compactMap { $0 })
            }
            let expl = "It is still writing" + (output.map { " to \($0)" } ?? "") + (e.lastOutput.map { ", most recently at \(Fmt.time($0))" } ?? "")
                + ", so it is doing something, but it doesn't report how far along it is. \(started)"
            return Card(state: state, headline: "\(who) is working: it is still writing output. It doesn't say how far along it is.",
                        explanation: expl,
                        fixes: [wait(until: nil, now: now, recommended: !warm || cooler == nil), cooler.map { var c = $0; c.recommended = warm; return c }, stop].compactMap { $0 })
        case .waiting:
            let holder = e.locks.compactMap(\.note).first { !$0.contains("\(e.pid)") }
            return Card(state: state, headline: "\(who) is waiting for another job to finish first.",
                        explanation: "Its log says \u{201C}\(e.lastLine ?? "waiting")\u{201D}, and it isn't using the processor." + (holder.map { " The other job: \($0)." } ?? ""),
                        fixes: [wait(until: nil, now: now, recommended: true), stop].compactMap { $0 })
        case .stalled:
            let at = e.progress.map { Fmt.time($0.lineTime) } ?? "a while"
            let doing = e.coresNow >= 0.25 ? "busy" : "idle"
            return Card(state: state, headline: "\(who) has been \(doing) with no progress since \(at). It looks stuck.",
                        explanation: "Its last progress line, \u{201C}\(e.progress?.line ?? "")\u{201D}, was written at \(at). It usually reports more often than that. \(started)",
                        fixes: [stop ?? lookUp(e.name, recommended: true), wait(until: nil, now: now, recommended: false)])
        case .unknown:
            return Card(state: state,
                        headline: "\(who) has used about \(Fmt.cores(max(e.coresNow, e.coresAverage))) for \(Fmt.duration(busyFor)). Can't tell whether it is working or stuck.",
                        explanation: "It reports no progress and isn't writing any files, so there is nothing to judge it by. \(started)",
                        fixes: [lookUp(e.script ?? e.name, recommended: true), wait(until: nil, now: now, recommended: false), cooler, stop].compactMap { $0 })
        case .starting:
            return Card(state: state, headline: "\(who) is busy, and only started \(Fmt.duration(busyFor)) ago.",
                        explanation: started, fixes: [wait(until: nil, now: now, recommended: true), cooler, stop].compactMap { $0 })
        case .quiet:
            return Card(state: state, headline: "\(who) is quiet right now.", explanation: started, fixes: [])
        }
    }
}

/// Formats in Phil's style: 4:50pm, 3 hours 20 minutes.
public enum Fmt {
    public static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.component(.minute, from: d) == 0 ? "ha" : "h:mma"
        let s = f.string(from: d).lowercased()
        let cal = Calendar.current
        if cal.isDateInToday(d) { return s }
        if cal.isDateInTomorrow(d) { return "\(s) tomorrow" }
        if cal.isDateInYesterday(d) { return "\(s) yesterday" }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "d MMMM"
        return "\(s) on \(day.string(from: d))"
    }

    public static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 1 { return "under a minute" }
        if m < 60 { return m == 1 ? "1 minute" : "\(m) minutes" }
        let h = m / 60, r = m % 60
        let hs = h == 1 ? "1 hour" : "\(h) hours"
        return r == 0 ? hs : "\(hs) \(r) minute\(r == 1 ? "" : "s")"
    }

    /// A clock time alone, for chart labels: 11:59pm.
    public static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.component(.minute, from: d) == 0 ? "ha" : "h:mma"
        return f.string(from: d).lowercased()
    }

    public static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded(.down)))%" }

    public static func cores(_ c: Double) -> String {
        if c < 0.95 { return "\(Int((c * 100).rounded()))% of one core" }
        let r = (c * 2).rounded() / 2
        let s = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
        return r == 1 ? "1 core" : "\(s) cores"
    }

    public static func bytes(_ b: UInt64) -> String {
        let g = Double(b) / 1_073_741_824
        return g >= 1 ? String(format: "%.1f GB", g) : "\(Int(Double(b) / 1_048_576)) MB"
    }
}
