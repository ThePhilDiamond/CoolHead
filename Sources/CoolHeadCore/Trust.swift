import Foundation

/// Apps and jobs the person has chosen to trust: Cool Head stops flagging them for ordinary heat or busyness, but
/// still flags them past a limit, so nothing can be hidden indefinitely (Phil, 15 November 2026: "My worry is that
/// they could end up having hidden something dangerous indefinitely").
///
/// The one thing Cool Head keeps between launches besides its settings: the list itself, on this Mac only (an app's
/// bundle identifier, or a script's or program's location, with the name to show). Nothing about what happened.
/// Listed and removable from the right-click menu.
public enum Trust {
    static let defaultsKey = "trusted"
    /// How long a trusted item may stay busy without a break before it is flagged anyway.
    public static let limitHours: Double = 8

    /// Trusted items: key → the name to show.
    public static var all: [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
    public static func contains(_ key: String?) -> Bool { key.map { all[$0] != nil } ?? false }
    public static func add(_ key: String, name: String) {
        var d = all; d[key] = name; UserDefaults.standard.set(d, forKey: defaultsKey)
    }
    public static func remove(_ key: String) {
        var d = all; d.removeValue(forKey: key); UserDefaults.standard.set(d, forKey: defaultsKey)
    }

    /// What it means to trust something, in one line, for the card.
    public static let promise = "Trusted. We still flag it if it looks stuck, your Mac gets hot, or it runs nonstop for \(Int(limitHours)) hours."

    /// Why a trusted item is flagged anyway, in a few words, or nil while it is within its limits.
    public static func overLimit(state: JobState, thermal: String, busyFor: TimeInterval) -> String? {
        if state == .stalled { return "it looks stuck" }
        if thermal == "serious" || thermal == "critical" { return "your Mac is hot" }
        if busyFor >= limitHours * 3600 { return "it has been busy for over \(Int(limitHours)) hours" }
        return nil
    }

    /// What identifies a process for trusting. A script by its own location (trusting one export.py doesn't trust
    /// every Python script); an app by its bundle identifier, so a helper inside it counts too; a program by its
    /// location. macOS's own processes can't be trusted: they're explained instead.
    public static func key(_ e: Evidence) -> String? {
        if e.script != nil, let s = scriptPath(e) { return "script:" + s }
        guard let p = e.path, !CaseReport.isMacOS(p) else { return nil }
        if let r = p.range(of: ".app/") { return key(appPath: String(p[..<r.lowerBound]) + ".app") }
        return "program:" + p
    }

    public static func key(appPath: String) -> String {
        "app:" + (Bundle(path: appPath)?.bundleIdentifier ?? appPath)
    }

    /// The full location of the script a runtime is running, from its arguments and working folder.
    static func scriptPath(_ e: Evidence) -> String? {
        guard let s = e.script, let a = e.args.dropFirst().first(where: { ($0 as NSString).lastPathComponent == s }) else { return nil }
        if a.hasPrefix("/") { return (a as NSString).standardizingPath }
        guard let cwd = e.cwd else { return nil }
        return ((cwd as NSString).appendingPathComponent(a) as NSString).standardizingPath
    }
}
