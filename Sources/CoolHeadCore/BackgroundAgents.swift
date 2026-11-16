import Foundation

/// Another app's background helper, started by launchd from a plist in ~/Library/LaunchAgents or /Library/LaunchAgents
/// (research node N-009, finding F5, from launchctl(1) on macOS 26.6.2). Stopping such a helper doesn't last: launchd
/// starts it again if its plist says to keep it alive, and at the next login anyway. Turning it off does:
/// `launchctl disable gui/<uid>/<label>` keeps it from loading, across restarts, and `bootout` stops it now. Neither
/// needs an administrator password in your own login session (only the system domain does). Undone with `enable`, then
/// `bootstrap` from the same plist.
///
/// Only other apps' helpers: never macOS's own (labels starting com.apple., or a program in macOS's folders), never
/// security software (see `SecuritySoftware`), and never an app you use (the Watcher leaves out regular apps: those are
/// quit instead, which lets them ask to save).
public enum BackgroundAgents {
    public struct Agent: Equatable, Codable {
        public let label: String
        public let plist: String
        public let program: String
        /// Who it belongs to, as shown: the app it's inside ("Google Updater"), or else its label.
        public let owner: String
    }

    public static var folders: [String] { [NSHomeDirectory() + "/Library/LaunchAgents", "/Library/LaunchAgents"] }
    /// What Cool Head turned off, so it can be undone from the top of the panel.
    public static let marker = "agentsTurnedOff"
    public static var domain: String { "gui/\(getuid())" }

    /// The program a plist starts: Program, or the first of ProgramArguments.
    static func program(_ d: [String: Any]) -> String? {
        (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first
    }

    /// The app a program is inside, by the outermost .app in its path ("…/GoogleUpdater.app/Contents/MacOS/…" →
    /// "GoogleUpdater"), or nil.
    static func appName(_ program: String) -> String? {
        guard let r = program.range(of: ".app/") else { return nil }
        return ((String(program[..<r.lowerBound]) as NSString).lastPathComponent)
    }

    /// One plist, read as a file (nothing is run). Nil for macOS's own, for one that runs a macOS program (a shell
    /// running a command could be anything), and for security software.
    public static func agent(plist path: String) -> Agent? {
        guard let data = FileManager.default.contents(atPath: path),
              let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let label = d["Label"] as? String, !label.hasPrefix("com.apple."),
              let prog = program(d), prog.hasPrefix("/"), !CaseReport.isMacOS(prog),
              SecuritySoftware.product(path: prog, name: (prog as NSString).lastPathComponent) == nil else { return nil }
        return Agent(label: label, plist: path, program: prog, owner: appName(prog) ?? label)
    }

    /// Every helper in these folders.
    public static func all(in dirs: [String] = folders) -> [Agent] {
        dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".plist") }.sorted()
                .compactMap { agent(plist: dir + "/" + $0) }
        }
    }

    static func resolve(_ p: String) -> String { (p as NSString).resolvingSymlinksInPath }

    /// The helper that runs one of these programs, tried in order (the busy process's own program first, then the ones
    /// that started it, up to the first regular app).
    public static func owner(of programs: [String], in dirs: [String] = folders) -> Agent? {
        guard !programs.isEmpty else { return nil }
        let agents = cache.agents(dirs)
        for p in programs.map(resolve) {
            if let a = agents.first(where: { resolve($0.program) == p }) { return a }
        }
        return nil
    }

    /// The plists are read again only when a folder changes, so a card costs no file reads after the first.
    final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var key = ""
        var list: [Agent] = []
        func agents(_ dirs: [String]) -> [Agent] {
            let k = dirs.map { d in "\(d):\(((try? FileManager.default.attributesOfItem(atPath: d))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" }
                .joined(separator: "|")
            lock.lock(); defer { lock.unlock() }
            if k != key { list = BackgroundAgents.all(in: dirs); key = k }
            return list
        }
    }
    static let cache = Cache()

    // MARK: turning off and on

    @discardableResult
    static func launchctl(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Loaded in your login session now.
    public static func isLoaded(_ label: String) -> Bool { launchctl(["print", "\(domain)/\(label)"]).status == 0 }

    /// Kept from loading: listed by `launchctl print-disabled` as disabled (older macOS writes "true").
    public static func isDisabled(_ label: String) -> Bool {
        launchctl(["print-disabled", domain]).output.split(separator: "\n").contains { line in
            line.contains("\"\(label)\"") && (line.contains("=> disabled") || line.contains("=> true"))
        }
    }

    /// Turns it off: kept from loading at login, and stopped now. True when both took.
    @discardableResult
    public static func turnOff(_ a: Agent, marker m: String = marker) -> Bool {
        guard !a.label.hasPrefix("com.apple.") else { return false }
        launchctl(["disable", "\(domain)/\(a.label)"])
        launchctl(["bootout", "\(domain)/\(a.label)"])
        let ok = isDisabled(a.label) && !isLoaded(a.label)
        if isDisabled(a.label) { record(a, on: true, marker: m) }
        return ok
    }

    /// Turns it back on: allowed to load, and loaded from its plist now (it runs if its plist says to run at load).
    @discardableResult
    public static func turnOn(_ a: Agent, marker m: String = marker) -> Bool {
        launchctl(["enable", "\(domain)/\(a.label)"])
        if !isLoaded(a.label) { launchctl(["bootstrap", domain, a.plist]) }
        let ok = !isDisabled(a.label) && isLoaded(a.label)
        if !isDisabled(a.label) { record(a, on: false, marker: m) }
        return ok
    }

    /// What Cool Head turned off and is still off (one turned back on some other way drops off the list).
    public static func turnedOff(marker m: String = marker) -> [Agent] {
        saved(m).filter { isDisabled($0.label) }
    }

    static func saved(_ m: String) -> [Agent] {
        UserDefaults.standard.data(forKey: m).flatMap { try? JSONDecoder().decode([Agent].self, from: $0) } ?? []
    }

    static func record(_ a: Agent, on: Bool, marker m: String) {
        var list = saved(m).filter { $0.label != a.label }
        if on { list.append(a) }
        if list.isEmpty { UserDefaults.standard.removeObject(forKey: m) }
        else { UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: m) }
    }

    /// The option, for a card about a process this helper runs.
    public static func fix(_ a: Agent) -> Fix {
        let what = a.owner == a.label ? "Whatever it does stops too." : "Whatever it does for \(a.owner), such as updates or syncing, stops too."
        return Fix(id: "agent", title: "Stop it starting by itself",
                   consequence: "Stops it now and at every login. \(what) Undo any time.",
                   kind: .stopAgent(a.label, a.plist))
    }
}
