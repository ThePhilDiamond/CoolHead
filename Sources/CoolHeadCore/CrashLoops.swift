import Foundation

/// An app that crashes again and again (research rule 22, node N-017): a crash loop never stays up long enough to look
/// busy, so it shows only in macOS's crash reports. Read from the reports' file names and first lines only (the app's
/// name, its bundle ID, the time and the kind of report), never the crash details. The person's own folder is always
/// readable; macOS's system folder only on an administrator's account (it belongs to the `_analyticsusers` group).
/// Mac restarts and panics are read separately, in Hardware.swift.
public enum CrashLoops {
    public struct Crash: Equatable {
        public var app: String
        public var bundle: String?
        public var time: Date
        public init(app: String, bundle: String?, time: Date) { self.app = app; self.bundle = bundle; self.time = time }
    }

    public struct Loop: Equatable {
        public var app: String
        public var bundle: String?
        public var count: Int
        public var first: Date
        public var last: Date
    }

    /// Cool Head's own threshold, not Apple's: 5 or more crashes of one app in the last 24 hours. One crash is
    /// ordinary; a handful in a day means it can't stay running.
    public static let minimum = 5
    public static let window: TimeInterval = 24 * 3600

    public static let folders = [NSHomeDirectory() + "/Library/Logs/DiagnosticReports", "/Library/Logs/DiagnosticReports"]

    /// The time in a report's header: "2026-11-17 09:15:02.00 -0800".
    static let stamp: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z"].map { f in
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = f; return d
    }

    /// A crash report's first line (macOS 12 and later): a JSON header. Only app crashes (`bug_type` 309) count; hang,
    /// memory and other reports share the folder.
    public static func parseHeader(_ line: String) -> Crash? {
        guard let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (o["bug_type"] as? String) == "309",
              let name = (o["app_name"] as? String) ?? (o["name"] as? String), !name.isEmpty,
              let ts = o["timestamp"] as? String,
              let time = stamp.lazy.compactMap({ $0.date(from: ts) }).first else { return nil }
        return Crash(app: name, bundle: o["bundleID"] as? String, time: time)
    }

    /// Apps with `minimum` or more crashes in the `window` before `now`, most crashes first. macOS's own (a `com.apple.`
    /// bundle ID) aren't counted: the card's advice, updating the app, is for apps you installed.
    public static func loops(_ crashes: [Crash], now: Date) -> [Loop] {
        let recent = crashes.filter { $0.time <= now && now.timeIntervalSince($0.time) <= window && !($0.bundle?.hasPrefix("com.apple.") ?? false) }
        let groups = Dictionary(grouping: recent) { $0.bundle ?? $0.app }
        return groups.values.compactMap { g -> Loop? in
            guard g.count >= minimum, let first = g.map(\.time).min(), let last = g.map(\.time).max() else { return nil }
            return Loop(app: g[0].app, bundle: g[0].bundle, count: g.count, first: first, last: last)
        }.sorted { ($0.count, $0.app) > ($1.count, $1.app) }
    }

    static let console = "/System/Applications/Utilities/Console.app"

    /// One card for each app crashing in a loop. The text gives the count and what it costs; the options look it up
    /// and show the reports.
    public static func cards(_ loops: [Loop]) -> [LiveCard] {
        loops.map { l in
            var c = LiveCard(id: "crash-loop-\(l.bundle ?? l.app)", pid: nil, card: Card(
                state: .unknown,
                CardTemplate(l.app, .words("crashed \(l.count) times, starting at \(Fmt.time(l.first))"), .moreThanUsual,
                             evidence: ["An app that crashes this often cannot stay open, and macOS writes a report each time, which takes about a minute of work."],
                             effect: ["Update it first. If it keeps crashing, reinstall it or tell its developer."]),
                fixes: [Card.lookUp("\(l.app) keeps crashing on Mac", recommended: true),
                        Fix.openApp("console", "See the crash reports", bundle: console, steps: "Choose Crash Reports, then \(l.app).")]),
                details: [])
            c.nerdy = NerdyStuff.facts([], source: .reports,
                                         verdict: ["Shown when an app that is not macOS's own crashes \(minimum) times or more in \(Fmt.duration(window))."],
                                         card: c.card, before: [
                                            .init("Crashes in the last 24 hours", "\(l.count), the first at \(Fmt.time(l.first)), the latest at \(Fmt.time(l.last))", .reports,
                                                  check: "ls -lt ~/Library/Logs/DiagnosticReports /Library/Logs/DiagnosticReports | head -20")],
                                         identity: ["App: \(l.app)" + (l.bundle.map { ", \($0)" } ?? "")])
            c.causeKey = "crash-loop-\(l.bundle ?? l.app)"
            c.displaySubject = l.app
            c.reportSubject = "an app that keeps crashing"
            return c
        }
    }

    /// This Mac's crashes in the last 24 hours, from both folders, and whether the system folder could be read. Only
    /// files changed in the window are opened, and only their first line is read.
    public static func read(now: Date = Date()) -> (crashes: [Crash], systemReadable: Bool) {
        var out: [Crash] = []
        var systemReadable = false
        let fm = FileManager.default
        for folder in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            if folder.hasPrefix("/Library") { systemReadable = true }
            for name in names where name.hasSuffix(".ips") {
                let path = folder + "/" + name
                guard let changed = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                      now.timeIntervalSince(changed) <= window,
                      let h = FileHandle(forReadingAtPath: path) else { continue }
                let head = (try? h.read(upToCount: 4096)) ?? Data()
                try? h.close()
                let first = String(decoding: head, as: UTF8.self).split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
                if let c = parseHeader(first) { out.append(c) }
            }
        }
        return (out, systemReadable)
    }
}
