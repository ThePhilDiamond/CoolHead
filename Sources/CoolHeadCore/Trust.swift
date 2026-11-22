import Foundation

/// Apps and jobs the person has chosen to trust: Cool Head stops flagging them for ordinary heat or busyness, but still
/// flags them past a limit, so nothing, something dangerous included, can stay hidden indefinitely.
///
/// The one thing Cool Head keeps between launches besides its settings: the list itself, on this Mac only (an app's
/// bundle identifier, or a script's or program's location, with the name to show). Nothing about what happened.
/// Listed under Trusted, along the bottom of the panel: + trusts an app, − stops trusting one.
public enum Trust {
    static let defaultsKey = "trusted"
    /// Where the trusted list and Always cooler (CoolerRules) are kept: the app's own settings; the selftest swaps in a
    /// throwaway set so it never touches them.
    nonisolated(unsafe) static var defaults = UserDefaults.standard
    /// How long a trusted item may stay busy without a break before it is flagged anyway.
    public static let limitHours: Double = 8

    /// Trusted items: key → the name to show.
    public static var all: [String: String] {
        defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
    public static func contains(_ key: String?) -> Bool { key.map { all[$0] != nil } ?? false }
    /// Trusts it, and takes it off Always cooler: leaving something alone and always slowing it are opposites.
    public static func add(_ key: String, name: String) {
        var d = all; d[key] = name; defaults.set(d, forKey: defaultsKey)
        CoolerRules.forget(key)
    }
    public static func remove(_ key: String) { forget(key) }
    /// Stops trusting it without touching Always cooler (what CoolerRules.add uses).
    static func forget(_ key: String) {
        var d = all
        guard d.removeValue(forKey: key) != nil else { return }
        defaults.set(d, forKey: defaultsKey)
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
        key(path: e.path, name: e.name, args: e.args, cwd: e.cwd)
    }

    /// The same, from a process's location, name, arguments and working folder, for matching Always cooler's rules
    /// against every process without gathering everything a card needs.
    public static func key(path: String?, name: String, args: [String], cwd: String?) -> String? {
        if let script = Evidence.script(path: path, name: name, args: args), let s = scriptPath(script: script, args: args, cwd: cwd) {
            return "script:" + s
        }
        guard let p = path, !CaseReport.isMacOS(p) else { return nil }
        if let r = p.range(of: ".app/") { return key(appPath: String(p[..<r.lowerBound]) + ".app") }
        return "program:" + p
    }

    public static func key(appPath: String) -> String {
        "app:" + (Bundle(path: appPath)?.bundleIdentifier ?? appPath)
    }

    /// The full location of the script a runtime is running, from its arguments and working folder.
    static func scriptPath(script s: String, args: [String], cwd: String?) -> String? {
        guard let a = args.dropFirst().first(where: { ($0 as NSString).lastPathComponent == s }) else { return nil }
        if a.hasPrefix("/") { return (a as NSString).standardizingPath }
        guard let cwd else { return nil }
        return ((cwd as NSString).appendingPathComponent(a) as NSString).standardizingPath
    }
}
