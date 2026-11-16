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
    /// What it is, for naming it apart from others (see `Naming`); for a program that isn't an app, whether it was run
    /// from a terminal. Taken from `kind` when not set.
    public var what: Naming.What? = nil

    public var named: Naming.Named {
        let w: Naming.What
        switch kind {
        case .browser, .app: w = .app
        case .job: w = .script
        case .macOS: w = .macOS
        case .other: w = what ?? .background
        }
        return Naming.Named(MemoryAdvice.label(self), w)
    }
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

    /// What quitting a sync app costs: nothing is lost; it stops syncing and catches up when it's opened again.
    static let syncQuit = "Syncing stops until you open it again, then catches up. Nothing is lost."

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
        var g = MemGroup(key: "other-\(name)", name: name, kind: .other, bundle: nil, bytes: footprint, count: 1)
        g.what = Naming.what(path: path, hasTerminal: Proc.bsd(pid)?.hasTerminal ?? false)
        return g
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
    /// `chrome`: whether Chrome's memory limit can be set; read from Chrome's settings when not given.
    public static func card(_ groups: [MemGroup], mac s: MacState, now: Date = Date(), chrome: ChromeLimit.Status? = nil) -> Card {
        let tight = s.memoryPressure == "critical" ? "Memory is very tight." : "Memory is tight."
        guard let top = groups.first else {
            return Card(state: .unknown, headline: tight, explanation: pressure(s),
                        fixes: [Fix.openApp("quitunused", "Quit apps you aren't using", bundle: Fix.activityMonitor, steps: "Click Memory to see which use the most. Each app asks to save before it quits.", recommended: true)])
        }
        let size = Fmt.bytes(top.bytes)
        // the three biggest, named so they can be told apart (see Naming)
        let shown = Array(groups.prefix(3))
        let names = Naming.distinct(shown.map(\.named))
        let head = "\(tight) \(Fmt.sentenceStart(names[0])) is using the most (\(size))."
        // the next biggest, by name, so the card shows where the rest of the memory is (the biggest is in the headline)
        let next = zip(shown.dropFirst(), names.dropFirst()).map { "\($1) (\(Fmt.bytes($0.bytes)))" }
        let expl = pressure(s) + (next.isEmpty ? "" : " Also using a lot: \(ListFormatter.localizedString(byJoining: next)).")
        var fixes: [Fix] = []
        var limitNote: String? = nil

        switch top.kind {
        case .browser:
            let menu = top.name == "Safari" ? "Choose Window ▸ Activity" : top.name == "Firefox" ? "Type about:processes in the address bar" : "Choose Window ▸ Task Manager"
            fixes.append(top.bundle.map { Fix.openApp("tabs", "Close \(top.name)'s heaviest tabs", bundle: $0, steps: "\(menu), then click Memory to put the biggest first.", recommended: true) }
                         ?? Fix.guide("tabs", "Close \(top.name)'s heaviest tabs", "In \(top.name): \(menu.prefix(1).lowercased() + menu.dropFirst()), then click Memory.",
                                      steps: ["In \(top.name): \(menu.prefix(1).lowercased() + menu.dropFirst()).", "Click Memory to put the biggest first.", "Close the tabs at the top that you don't need."], recommended: true))
            if top.name == "Google Chrome" {
                let st = chrome ?? ChromeLimit.status(chromeUse: top.bytes)
                if let limit = ChromeLimit.fix(st) { fixes.append(limit) }
                limitNote = ChromeLimit.note(st, using: top.bytes)
                if let b = top.bundle {
                    fixes.append(Fix(id: "saver", title: "Turn on Memory Saver", consequence: "Takes you to Chrome's Performance settings. Tabs you aren't using sleep, and reload when you click them.", kind: .openPage(b, "chrome://settings/performance")))
                }
            } else if top.name == "Microsoft Edge" {
                if let b = top.bundle {
                    fixes.append(Fix(id: "saver", title: "Turn on sleeping tabs", consequence: "Takes you to Edge's System and performance settings. Tabs you aren't using sleep, and reload when you click them.", kind: .openPage(b, "edge://settings/system")))
                }
            }
            if let b = top.bundle {
                fixes.append(Fix(id: "quit", title: "Quit \(top.name)", consequence: "Frees \(size). Closes all tabs.", kind: .quitApp(b)))
            }
        case .app:
            if let b = top.bundle, let sync = SyncApps.app(bundle: b) {
                // a sync app: quitting frees its memory and loses nothing, unlike an app with unsaved work; pausing
                // keeps it open, so it stops it working harder but doesn't give its memory back
                fixes.append(Fix(id: "quit", title: "Quit \(sync)", consequence: "Frees \(size). " + syncQuit, kind: .quitApp(b), recommended: true))
                fixes.append(Fix(id: "pause", title: "Pause syncing", consequence: "Opens \(sync) so you can pause it; we'll remind you to resume. It stays open, so its memory isn't freed.",
                                 kind: .pauseSync(b, sync)))
            } else if let b = top.bundle, SecuritySoftware.product(path: b + "/", name: top.name) == nil {   // never security software
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
        // Chrome among the biggest, but not the biggest: limiting it is a way to free memory that closes nothing
        // (found in the live test, 15 November 2026: Google Drive 4.7 GB, Chrome 4.6 GB, and only Quit was offered)
        if top.name != "Google Chrome", let c = groups.prefix(3).first(where: { $0.name == "Google Chrome" && $0.kind == .browser }) {
            let st = chrome ?? ChromeLimit.status(chromeUse: c.bytes)
            if let limit = ChromeLimit.fix(st) { fixes.append(limit) }
            limitNote = ChromeLimit.note(st, using: c.bytes)
        }
        // a Chromium browser among the biggest: restarting it frees the memory it has built up, and its tabs come back
        // (see BrowserRestart); before Quit, since it loses less, and never recommended, since it closes the browser
        // you may be using and doesn't bring back private windows, unsent form text or downloads
        if let r = groups.prefix(3).first(where: { $0.kind == .browser && BrowserRestart.browsers.contains($0.name) && $0.bundle != nil }), let b = r.bundle {
            fixes.append(Fix(id: "restart", title: "Restart \(r.name), keeping your tabs",
                             consequence: "Closes and reopens \(r.name), freeing memory it built up. Your tabs come back; \(BrowserRestart.privateWindows(r.name)), unsent form text, and downloads in progress don't.",
                             kind: .restartBrowser(b)))
        }
        // the next largest app that can be quit, as a second way to free memory
        if let alt = groups.dropFirst().first(where: { ($0.kind == .app || $0.kind == .browser) && $0.bundle != nil
                                                        && SecuritySoftware.product(path: $0.bundle! + "/", name: $0.name) == nil }), let b = alt.bundle {
            let risk = alt.kind == .browser ? "Closes all tabs." : SyncApps.app(bundle: b) != nil ? syncQuit : (quitRisks[alt.name] ?? "It'll ask to save first.")
            fixes.append(Fix(id: "quit2", title: "Quit \(alt.name) instead", consequence: "Frees \(Fmt.bytes(alt.bytes)). " + risk, kind: .quitApp(b)))
        }
        fixes.append(Fix(id: "wait", title: "Wait 30 minutes", consequence: "Your Mac stays slow for now.",
                         kind: .wait(now.addingTimeInterval(1800)), recommended: !fixes.contains { $0.recommended }))
        var card = Card(state: .unknown, headline: head, explanation: expl + (limitNote.map { " " + $0 } ?? ""), fixes: fixes)
        card.names = names
        return card
    }

    /// Why tight memory matters, in one line; it mentions swap only when the Mac is actually using it.
    static func pressure(_ s: MacState) -> String {
        s.swapUsedMB > 50 ? "Your Mac is using its disk as extra memory, which is slow." : "When memory runs low, your Mac slows down."
    }
}
