import Foundation

/// Whether a busy process is doing its job, and how we know.
public enum State: String {
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

    public static func assess(_ e: Evidence, now: Date = Date()) -> State {
        let busy = e.coresNow >= 0.25
        let ran = now.timeIntervalSince(e.start ?? now)
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

/// The two lines the user sees: what it is and whether it is fine, then one action; plus, when stopping would cost
/// something, one line saying what.
public struct Card {
    public let state: State
    public let headline: String
    public let action: String
    public let caution: String?

    public static func make(_ e: Evidence, now: Date = Date()) -> Card {
        let who = e.project.map { "Your \($0) job \(e.task)" } ?? (e.script != nil ? "Your script \(e.task)" : e.name)
        let state = Health.assess(e, now: now)
        let atStake = now.timeIntervalSince(e.workStart ?? e.start ?? now)
        let loss: String? = {
            guard atStake >= 10 * 60 else { return nil }
            return e.savesAsItGoes
                ? "It saves results as it goes, so stopping it would lose only the latest part."
                : "Stopping it now would lose about \(Fmt.duration(atStake)) of work."
        }()

        switch state {
        case .working:
            if let p = e.progress {
                var line = "\(who) is " + (p.fraction.map { "\(Fmt.percent($0)) done." } ?? "making progress.")
                if let fin = p.finish { line += fin > now ? " Done around \(Fmt.time(fin))." : " It should finish any minute." }
                return Card(state: state, headline: line, action: "Let it finish", caution: loss)
            }
            return Card(state: state, headline: "\(who) is working: it is still writing output. It doesn't report progress, so there is no finish time.",
                        action: "Let it run", caution: loss)
        case .waiting:
            let holder = e.locks.compactMap(\.note).first { !$0.contains("\(e.pid)") }
            return Card(state: state, headline: "\(who) is waiting for another job to finish first" + (holder.map { " (\($0))." } ?? "."),
                        action: "Nothing to do", caution: nil)
        case .stalled:
            let since = e.progress.map { Fmt.time($0.lineTime) } ?? "a while"
            let doing = e.coresNow >= 0.25 ? "busy" : "idle"
            return Card(state: state, headline: "\(who) has been \(doing) with no progress since \(since). It looks stuck.",
                        action: "Stop it and run it again",
                        caution: "It has done nothing new since \(since), so stopping it loses nothing after that.")
        case .unknown:
            return Card(state: state,
                        headline: "\(who) has used about \(Fmt.cores(max(e.coresNow, e.coresAverage))) for \(Fmt.duration(now.timeIntervalSince(e.start ?? now))). Can't tell whether it is working or stuck.",
                        action: "Look it up",
                        caution: loss.map { "Don't stop it until you know what it is. If it is a long job: " + $0.prefix(1).lowercased() + $0.dropFirst() })
        case .starting:
            return Card(state: state, headline: "\(who) is busy, and only started \(Fmt.duration(now.timeIntervalSince(e.start ?? now))) ago.",
                        action: "Nothing to do", caution: nil)
        case .quiet:
            return Card(state: state, headline: "\(who) is quiet right now.", action: "Nothing to do", caution: nil)
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
        return Calendar.current.isDateInToday(d) ? s : "\(s) on \(DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none))"
    }

    public static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 1 { return "under a minute" }
        if m < 60 { return m == 1 ? "1 minute" : "\(m) minutes" }
        let h = m / 60, r = m % 60
        let hs = h == 1 ? "1 hour" : "\(h) hours"
        return r == 0 ? hs : "\(hs) \(r) minute\(r == 1 ? "" : "s")"
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
