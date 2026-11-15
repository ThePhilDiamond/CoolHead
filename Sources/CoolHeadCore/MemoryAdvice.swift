import Foundation

/// When memory is tight: who is using it, counted the way a person thinks of it (an app with all its helper
/// processes, or one job), and what can be done about each, with what doing it would cost.
public struct MemGroup {
    public enum Kind { case browser, app, job, macOS, other }
    public let key: String
    public let name: String
    public let kind: Kind
    /// The app's bundle path when it is installed in an Applications folder (so it can be quit).
    public let bundle: String?
    public var bytes: UInt64
    public var count: Int
    /// For a job: the process, to say what stopping it would cost.
    public var evidence: Evidence? = nil
    public var pid: pid_t? = nil
}

public enum MemoryAdvice {
    static let browsers = ["Google Chrome", "Safari", "Microsoft Edge", "Brave Browser", "Firefox", "Arc", "Opera", "Vivaldi", "Chromium"]

    /// What quitting costs for apps where it costs more than unsaved work.
    static let quitRisks: [String: String] = [
        "Docker": "Stops all containers.",
        "OrbStack": "Stops all containers and machines.",
        "Parallels Desktop": "Shuts down the virtual machine. Save inside it first.",
        "UTM": "Shuts down the virtual machine. Save inside it first.",
        "VMware Fusion": "Shuts down the virtual machine. Save inside it first.",
        "Xcode": "Stops builds and simulators.",
        "Final Cut Pro": "Stops renders and exports.",
        "Adobe Premiere Pro": "Stops renders and exports.",
        "DaVinci Resolve": "Stops renders and exports.",
        "Logic Pro": "Stops bounces. It'll ask to save.",
        "Slack": "No messages until you reopen it.",
        "Microsoft Teams": "Leaves calls. No messages until you reopen it.",
        "zoom.us": "Leaves your meeting.",
        "Claude": "Stops what Claude is doing.",
        "ChatGPT": "Ends the conversation in progress.",
        "Terminal": "Stops what's running in it.",
        "iTerm": "Stops what's running in it.",
        "Warp": "Stops what's running in it.",
        "Visual Studio Code": "Stops what's running in it.",
        "Cursor": "Stops what's running in it.",
        "Spotify": "Stops the music.",
        "Music": "Stops the music.",
    ]

    /// Puts each process in its group: the app it belongs to, a job of the person's, macOS, or itself.
    public static func group(pid: pid_t, path: String?, args: [String], footprint: UInt64) -> MemGroup? {
        guard footprint > 0 else { return nil }
        let scriptLike = args.count > 1 && args.dropFirst().contains { a in !a.hasPrefix("-") && (a.hasSuffix(".py") || a.hasSuffix(".js") || a.hasSuffix(".rb") || a.hasSuffix(".sh") || a.hasSuffix(".ts")) }
        if let p = path, let r = p.range(of: ".app/"), !scriptLike {
            let bundle = String(p[..<r.lowerBound]) + ".app"
            let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            if CaseReport.isMacOS(p) { return MemGroup(key: bundle, name: name, kind: .macOS, bundle: nil, bytes: footprint, count: 1) }
            let installed = bundle.hasPrefix("/Applications/") || bundle.hasPrefix(NSHomeDirectory() + "/Applications/")
            return MemGroup(key: bundle, name: name, kind: browsers.contains(name) ? .browser : .app,
                            bundle: installed && bundle.components(separatedBy: ".app/").count == 1 ? bundle : nil, bytes: footprint, count: 1)
        }
        if scriptLike { return MemGroup(key: "job-\(pid)", name: "a script", kind: .job, bundle: nil, bytes: footprint, count: 1, pid: pid) }
        let name = path.map { ($0 as NSString).lastPathComponent } ?? "process \(pid)"
        if let p = path, CaseReport.isMacOS(p) { return MemGroup(key: "macos-\(name)", name: name, kind: .macOS, bundle: nil, bytes: footprint, count: 1) }
        return MemGroup(key: "other-\(name)", name: name, kind: .other, bundle: nil, bytes: footprint, count: 1)
    }

    /// Adds processes of the same app together.
    public static func merge(_ groups: [MemGroup]) -> [MemGroup] {
        var by: [String: MemGroup] = [:]
        for g in groups {
            if var have = by[g.key] { have.bytes += g.bytes; have.count += g.count; by[g.key] = have } else { by[g.key] = g }
        }
        return by.values.sorted { $0.bytes > $1.bytes }
    }

    public static func label(_ g: MemGroup) -> String {
        if g.kind == .job, let e = g.evidence { return Card.subject(e) }
        return g.name
    }

    /// The card. `groups` sorted largest first, with `evidence` filled in for jobs.
    public static func card(_ groups: [MemGroup], mac s: MacState, now: Date = Date()) -> Card {
        let tight = s.memoryPressure == "critical" ? "Memory is very tight." : "Memory is tight."
        guard let top = groups.first else {
            return Card(state: .unknown, headline: tight, explanation: pressure(s),
                        fixes: [Fix(id: "quitunused", title: "Quit apps you aren't using", consequence: "Frees memory. Each asks to save first.", kind: .info, recommended: true)])
        }
        let size = Fmt.bytes(top.bytes)
        let head = "\(tight) \(label(top)) is using the most (\(size))."
        let biggest = groups.prefix(3).map { "\(label($0)) \(Fmt.bytes($0.bytes))" }.joined(separator: ", ")
        let expl = pressure(s) + " Biggest: \(biggest)."
        var fixes: [Fix] = []

        switch top.kind {
        case .browser:
            let menu = top.name == "Safari" ? "Window ▸ Activity" : top.name == "Firefox" ? "type about:processes" : "Window ▸ Task Manager"
            fixes.append(Fix(id: "tabs", title: "Close \(top.name)'s heaviest tabs", consequence: "\(menu), sort by Memory.", kind: .info, recommended: true))
            if top.name == "Google Chrome" {
                fixes.append(Fix(id: "saver", title: "Turn on Memory Saver", consequence: "Chrome Settings ▸ Performance. Unused tabs nap.", kind: .info))
            } else if top.name == "Microsoft Edge" {
                fixes.append(Fix(id: "saver", title: "Turn on sleeping tabs", consequence: "Edge Settings ▸ System and performance.", kind: .info))
            }
            if let b = top.bundle {
                fixes.append(Fix(id: "quit", title: "Quit \(top.name)", consequence: "Frees \(size). Closes all tabs.", kind: .quitApp(b)))
            }
        case .app:
            if let b = top.bundle {
                let risk = quitRisks[top.name]
                fixes.append(Fix(id: "quit", title: "Quit \(top.name)", consequence: "Frees \(size). " + (risk ?? "It'll ask to save first."),
                                 kind: .quitApp(b), recommended: risk == nil))
            }
        case .job:
            if let e = top.evidence, let stop = Card.make(e, now: now).fixes.first(where: { $0.kind == .stop }) {
                fixes.append(Fix(id: "stop", title: "Stop it", consequence: "Frees \(size). " + stop.consequence, kind: .stop, recommended: false))
            }
        case .macOS, .other:
            fixes.append(Fix(id: "lookup", title: "Look it up", consequence: "Search the web for \u{201C}\(top.name)\u{201D}.", kind: .lookUp(top.name)))
        }
        // the next largest app that can be quit, as a second way to free memory
        if let alt = groups.dropFirst().first(where: { ($0.kind == .app || $0.kind == .browser) && $0.bundle != nil }), let b = alt.bundle {
            let risk = alt.kind == .browser ? "Closes all tabs." : (quitRisks[alt.name] ?? "It'll ask to save first.")
            fixes.append(Fix(id: "quit2", title: "Quit \(alt.name) instead", consequence: "Frees \(Fmt.bytes(alt.bytes)). " + risk, kind: .quitApp(b)))
        }
        fixes.append(Fix(id: "wait", title: "Wait 30 minutes", consequence: "Your Mac stays slow for now.",
                         kind: .wait(now.addingTimeInterval(1800)), recommended: !fixes.contains { $0.recommended }))
        return Card(state: .unknown, headline: head, explanation: expl, fixes: fixes)
    }

    /// Why tight memory matters, in one line; it mentions swap only when the Mac is actually using it.
    static func pressure(_ s: MacState) -> String {
        s.swapUsedMB > 50 ? "Your Mac is using its disk as extra memory, which is slow." : "When memory runs low, your Mac slows down."
    }
}
