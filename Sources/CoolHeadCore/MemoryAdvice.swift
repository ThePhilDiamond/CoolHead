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
        "Docker": "Quitting Docker stops every container.",
        "OrbStack": "Quitting OrbStack stops every container and machine.",
        "Parallels Desktop": "Quitting shuts down the virtual machine; save your work inside it first.",
        "UTM": "Quitting shuts down the virtual machine; save your work inside it first.",
        "VMware Fusion": "Quitting shuts down the virtual machine; save your work inside it first.",
        "Xcode": "Quitting stops any build, test or Simulator that is running.",
        "Final Cut Pro": "Quitting stops any render or export in progress.",
        "Adobe Premiere Pro": "Quitting stops any render or export in progress.",
        "DaVinci Resolve": "Quitting stops any render or export in progress.",
        "Logic Pro": "Quitting stops any bounce in progress; it asks you to save the project.",
        "Slack": "You won't get messages until you open it again.",
        "Microsoft Teams": "You'll leave any call you're in, and won't get messages until you open it again.",
        "zoom.us": "You'll leave any meeting you're in.",
        "Claude": "Quitting ends any conversation or task Claude is working on.",
        "ChatGPT": "Quitting ends any conversation in progress.",
        "Terminal": "Quitting stops everything running in its windows.",
        "iTerm": "Quitting stops everything running in its windows.",
        "Warp": "Quitting stops everything running in its windows.",
        "Visual Studio Code": "Quitting stops any terminal, build or task running inside it.",
        "Cursor": "Quitting stops any terminal, build or agent running inside it.",
        "Spotify": "Playback stops.",
        "Music": "Playback stops.",
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
        guard let top = groups.first else {
            return Card(state: .unknown, headline: "Memory is tight.", explanation: pressure(s), fixes: [Card.wait(until: nil, now: now, recommended: true)])
        }
        let size = Fmt.bytes(top.bytes)
        var head = "Memory is \(s.memoryPressure == "critical" ? "very " : "")tight. \(label(top)) is using the most, \(size)"
        head += top.count > 1 ? " across \(top.count) processes." : "."
        let others = groups.dropFirst().prefix(2).map { "\(label($0)) \(Fmt.bytes($0.bytes))" }
        var expl = pressure(s) + " Using the most: \(label(top)) \(size)" + (others.isEmpty ? "." : ", then " + others.joined(separator: " and ") + ".")
        var fixes: [Fix] = []

        switch top.kind {
        case .browser:
            expl += " Each tab and extension runs as its own process, so a few heavy pages can add up."
            let menu = top.name == "Safari" ? "Window ▸ Activity" : top.name == "Firefox" ? "about:processes in the address bar" : "Window ▸ Task Manager"
            fixes.append(Fix(id: "tabs", title: "Find the heaviest tabs: in \(top.name), open \(menu) and sort by memory",
                             consequence: "Close just those tabs. That frees their memory and keeps everything else open.", kind: .info, recommended: true))
            // a lasting fix that doesn't mean quitting: the browser hands back memory from tabs you aren't using
            if top.name == "Google Chrome" {
                fixes.append(Fix(id: "saver", title: "Turn on Memory Saver: in Google Chrome, open Settings ▸ Performance",
                                 consequence: "Tabs you aren't using give their memory back, and reload when you return to them.", kind: .info))
            } else if top.name == "Microsoft Edge" {
                fixes.append(Fix(id: "saver", title: "Turn on sleeping tabs: in Microsoft Edge, open Settings ▸ System and performance",
                                 consequence: "Tabs you aren't using give their memory back, and wake when you return to them.", kind: .info))
            }
            if let b = top.bundle {
                fixes.append(Fix(id: "quit", title: "Quit \(top.name)",
                                 consequence: "Frees about \(size). Closes every tab and window; \(top.name) can usually reopen them next time, but text typed into a page and not yet sent is lost.",
                                 kind: .quitApp(b)))
            }
        case .app:
            if let b = top.bundle {
                let risk = quitRisks[top.name]
                fixes.append(Fix(id: "quit", title: "Quit \(top.name)",
                                 consequence: "Frees about \(size). " + (risk ?? "It asks you to save anything open; anything it was doing in the background stops."),
                                 kind: .quitApp(b), recommended: risk == nil))
            }
        case .job:
            if let e = top.evidence, var stop = Card.make(e, now: now).fixes.first(where: { $0.kind == .stop }) {
                expl += " It's a job of yours; stopping it frees its memory."
                stop = Fix(id: "stop", title: "Stop it", consequence: "Frees about \(size). " + stop.consequence, kind: .stop, recommended: false)
                fixes.append(stop)
            }
        case .macOS:
            expl += " That is part of macOS, so the way to free memory is to close apps you aren't using."
            fixes.append(Fix(id: "lookup", title: "Look it up", consequence: "Opens a web search for \u{201C}\(top.name)\u{201D} in your browser. Nothing else is sent.",
                             kind: .lookUp(top.name)))
        case .other:
            fixes.append(Fix(id: "lookup", title: "Look it up", consequence: "Opens a web search for \u{201C}\(top.name)\u{201D} in your browser. Nothing else is sent.",
                             kind: .lookUp(top.name)))
        }
        // the next largest app that can be quit, as a second way to free memory
        if let alt = groups.dropFirst().first(where: { ($0.kind == .app || $0.kind == .browser) && $0.bundle != nil }), let b = alt.bundle {
            let risk = alt.kind == .browser ? "Closes every tab and window." : (quitRisks[alt.name] ?? "It asks you to save anything open.")
            fixes.append(Fix(id: "quit2", title: "Quit \(alt.name) instead", consequence: "Frees about \(Fmt.bytes(alt.bytes)). " + risk, kind: .quitApp(b)))
        }
        fixes.append(Fix(id: "wait", title: "Do nothing; check back in 30 minutes",
                         consequence: "Nothing changes: macOS keeps moving memory to disk, so the Mac stays slower. The card returns if memory is still tight.",
                         kind: .wait(now.addingTimeInterval(1800)), recommended: !fixes.contains { $0.recommended }))
        return Card(state: .unknown, headline: head, explanation: expl, fixes: fixes)
    }

    static func pressure(_ s: MacState) -> String {
        String(format: "macOS reports memory pressure as %@, and %.1f of %.1f GB of swap is in use: it is moving memory to the disk, which slows everything down.",
               s.memoryPressure, s.swapUsedMB / 1024, s.swapTotalMB / 1024)
    }
}
