import AppKit
import CoreGraphics
import Foundation

/// An app whose memory keeps growing with nothing new open: a leak (research rule 15).
///
/// Memory that falls when windows or documents close was work; memory that rises steadily while the same windows stay
/// open is a leak, and quitting and reopening the app gives it back (Howard Oakley, "What can you do when an app uses
/// too much memory?", 19 June 2026; version-specific reports in research node N-002). The method rests on one expert,
/// and the thresholds below are Cool Head's own, not from a source: at least two hours; grown by 2 GB or more and to at
/// least twice the first reading; never more than 10% lower than the reading before; the same number of windows
/// throughout (counted from macOS's window list by owner, which needs no permission and reads no window names).
public enum Leaks {
    public struct Sample: Equatable {
        public let at: Date
        public let bytes: UInt64
        public let windows: Int
        public init(at: Date, bytes: UInt64, windows: Int) { self.at = at; self.bytes = bytes; self.windows = windows }
    }

    public struct Leak: Equatable {
        public let from: UInt64
        public let to: UInt64
        public let since: Date
        public init(from: UInt64, to: UInt64, since: Date) { self.from = from; self.to = to; self.since = since }
    }

    public static let minimumSpan: TimeInterval = 2 * 3600
    public static let minimumGrowth: UInt64 = 2_000_000_000
    /// How often an app's memory is noted, and how long the notes are kept.
    public static let every: TimeInterval = 300
    public static let keep: TimeInterval = 6 * 3600

    /// A leak in these readings (oldest first), or nil.
    public static func judge(_ samples: [Sample]) -> Leak? {
        guard let first = samples.first, let last = samples.last, samples.count >= 3,
              last.at.timeIntervalSince(first.at) >= minimumSpan,
              last.bytes >= first.bytes + minimumGrowth, last.bytes >= first.bytes * 2,
              Set(samples.map(\.windows)).count == 1 else { return nil }
        for (a, b) in zip(samples, samples.dropFirst()) where Double(b.bytes) < Double(a.bytes) * 0.9 { return nil }
        return Leak(from: first.bytes, to: last.bytes, since: first.at)
    }

    /// Normal windows (layer 0, shown or not) per process, from macOS's window list. Owner and layer only.
    public static func windowCounts() -> [pid_t: Int] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var counts: [pid_t: Int] = [:]
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let p = w[kCGWindowOwnerPID as String] as? Int32 { counts[p, default: 0] += 1 }
        }
        return counts
    }

    /// Readings per app, kept for the watcher. An app that quit and opened again starts afresh.
    public final class Tracker: @unchecked Sendable {
        let lock = NSLock()
        var samples: [String: (pid: pid_t, list: [Sample])] = [:]
        var last = Date.distantPast
        public init() {}

        /// Whether it's time to note again.
        public func due(_ now: Date) -> Bool { lock.lock(); defer { lock.unlock() }; return now.timeIntervalSince(last) >= Leaks.every }

        /// Notes each app's memory (by its bundle) and windows (of its main process), at most every 5 minutes.
        public func note(_ apps: [(bundle: String, pid: pid_t, bytes: UInt64)], windows: () -> [pid_t: Int], now: Date) {
            lock.lock(); defer { lock.unlock() }
            guard now.timeIntervalSince(last) >= Leaks.every else { return }
            last = now
            let w = windows()
            var next: [String: (pid: pid_t, list: [Sample])] = [:]
            for a in apps {
                var list = samples[a.bundle].flatMap { $0.pid == a.pid ? $0.list : nil } ?? []
                list.append(Sample(at: now, bytes: a.bytes, windows: w[a.pid] ?? 0))
                next[a.bundle] = (a.pid, list.filter { now.timeIntervalSince($0.at) <= Leaks.keep })
            }
            samples = next
        }

        /// A leak in this app's readings: the longest stretch, ending now, that counts as one.
        public func leak(_ bundle: String) -> Leak? {
            lock.lock(); defer { lock.unlock() }
            guard let list = samples[bundle]?.list else { return nil }
            for start in list.indices { if let l = Leaks.judge(Array(list[start...])) { return l } }
            return nil
        }
    }

    /// "two hours", "11 hours": a number of hours in words for small numbers, so a sentence reads easily.
    static func hours(_ h: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return h == 1 ? "an hour" : (h < words.count ? words[h] : "\(h)") + " hours"
    }

    /// What the memory card says about a leaking app, anchored on what the same app used earlier with the same windows
    /// open (Phil, 16 November 2026: "anchor against typical use ... make it easy to make a decision"): a verdict for
    /// the headline, one sentence with the evidence and the advice, and the option, saving first. Caution only where
    /// quitting loses work (see MemoryAdvice.quitRisks).
    public static func addition(_ l: Leak, app: String, bundle: String, now: Date, losesWork: Bool) -> (headline: String, sentence: String, fix: Fix) {
        let h = max(2, Int(now.timeIntervalSince(l.since) / 3600))
        let headline = "\(app) is using \(Fmt.bytes(l.to)), far more than it needs."
        let sentence = "With the same windows open, it used \(Fmt.bytes(l.from)) \(hours(h)) ago: probably a leak. Save your work, then quit and reopen it."
        var fix = Fix(id: "reopen", title: "Quit and reopen \(app)",
                      consequence: "Save your work first. Gives back about \(Fmt.bytes(l.to - min(l.to, l.from))); some windows may not reopen.",
                      kind: .restartApp(bundle), recommended: true)
        if losesWork { fix = fix.losingWork() }
        return (headline, sentence, fix)
    }
}
