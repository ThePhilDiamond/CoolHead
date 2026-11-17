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

    /// What quitting costs, for apps where it costs more than unsaved work (the app asks to save that), and whether it
    /// loses something reopening can't bring back: work in progress, a call, what's running. Only those are Caution
    /// (Phil, 16 November 2026: "Caution should be reserved for actions like killing a process with unknown and/or
    /// irreversible consequences. There is risk attached. Whereas quitting Slack is not risky...").
    struct QuitCost {
        let words: String
        let losesWork: Bool
        static func keeps(_ w: String) -> QuitCost { QuitCost(words: w, losesWork: false) }
        static func loses(_ w: String) -> QuitCost { QuitCost(words: w, losesWork: true) }
    }
    static let quitRisks: [String: QuitCost] = [
        "Docker": .loses("Stops all containers."),
        "OrbStack": .loses("Stops all containers and machines."),
        "Parallels Desktop": .loses("Shuts down the virtual machine. Save inside it first."),
        "UTM": .loses("Shuts down the virtual machine. Save inside it first."),
        "VMware Fusion": .loses("Shuts down the virtual machine. Save inside it first."),
        "Xcode": .loses("Stops builds and simulators."),
        "Final Cut Pro": .loses("Stops renders and exports."),
        "Adobe Premiere Pro": .loses("Stops renders and exports."),
        "DaVinci Resolve": .loses("Stops renders and exports."),
        "Logic Pro": .loses("Stops bounces. It'll ask to save."),
        "Slack": .keeps("No messages until you reopen it."),
        "Microsoft Teams": .loses("Leaves calls. No messages until you reopen it."),
        "zoom.us": .loses("Leaves your meeting."),
        "Claude": .loses("Stops what Claude is doing."),
        "ChatGPT": .loses("Ends the conversation in progress."),
        "Terminal": .loses("Stops what's running in it."),
        "iTerm": .loses("Stops what's running in it."),
        "Warp": .loses("Stops what's running in it."),
        "Visual Studio Code": .loses("Stops what's running in it."),
        "Cursor": .loses("Stops what's running in it."),
        "Spotify": .keeps("Stops the music."),
        "Music": .keeps("Stops the music."),
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
    /// `models`: what Ollama has loaded, when it is among the biggest (see Leftovers); `buildData`: the size of Xcode's
    /// build data, when the startup disk is nearly full.
    public static func card(_ groups: [MemGroup], mac s: MacState, now: Date = Date(), chrome: ChromeLimit.Status? = nil,
                            models: [Leftovers.Model]? = nil, buildData: UInt64? = nil) -> Card {
        let tight = s.memoryPressure == "critical" ? "Memory is very tight." : "Memory is tight."
        guard let top = groups.first else {
            return Card(state: .unknown, headline: tight, explanation: pressure(s),
                        fixes: [Fix.openApp("quitunused", "Quit apps you aren't using", bundle: Fix.activityMonitor, steps: "Click Memory to see which use the most. Each app asks to save before it quits.", recommended: true).fixingTheCause()]
                            + (lowDisk(s) ? [Leftovers.buildDataFix(bytes: buildData).map { var f = $0; f.recommended = false; return f }, freeDisk].compactMap { $0 } : []))
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
        // a local AI model kept loaded after its last use: unloading it frees its memory and loses nothing, so when Ollama
        // is the biggest it's the recommendation (see Leftovers)
        if let m = models, shown.contains(where: { isOllama($0) }), let unload = Leftovers.unloadFix(m, recommended: isOllama(top)) {
            fixes.append(unload)
        }

        switch top.kind {
        case .browser:
            let menu = top.name == "Safari" ? "Choose Window ▸ Activity" : top.name == "Firefox" ? "Type about:processes in the address bar" : "Choose Window ▸ Task Manager"
            fixes.append((top.bundle.map { Fix.openApp("tabs", "Close \(top.name)'s heaviest tabs", bundle: $0, steps: "\(menu), then click Memory to put the biggest first.", recommended: true) }
                         ?? Fix.guide("tabs", "Close \(top.name)'s heaviest tabs", "In \(top.name): \(menu.prefix(1).lowercased() + menu.dropFirst()), then click Memory.",
                                      steps: ["In \(top.name): \(menu.prefix(1).lowercased() + menu.dropFirst()).", "Click Memory to put the biggest first.", "Close the tabs at the top that you don't need."], recommended: true)).fixingTheCause())
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
                fixes.append(Fix(id: "quit", title: "Quit \(top.name)", consequence: "Frees \(size). Closes all tabs.", kind: .quitApp(b)).losingWork())
            }
        case .app:
            if let b = top.bundle, let sync = SyncApps.app(bundle: b) {
                // a sync app: quitting frees its memory and loses nothing, unlike an app with unsaved work; pausing
                // keeps it open, so it stops it working harder but doesn't give its memory back
                fixes.append(Fix(id: "quit", title: "Quit \(sync)", consequence: "Frees \(size). " + syncQuit, kind: .quitApp(b), recommended: true))
                fixes.append(Fix(id: "pause", title: "Pause syncing", consequence: "Opens \(sync) so you can pause it; we'll remind you to resume. It stays open, so its memory isn't freed.",
                                 kind: .pauseSync(b, sync)))
            } else if let b = top.bundle, SecuritySoftware.product(path: b + "/", name: top.name) == nil {   // never security software
                // recommended when quitting loses nothing reopening can't bring back (Slack, or an app that asks to save)
                let cost = quitRisks[top.name]
                var quit = Fix(id: "quit", title: "Quit \(top.name)", consequence: "Frees \(size). " + (cost?.words ?? "It'll ask to save first."),
                               kind: .quitApp(b), recommended: cost?.losesWork != true)
                if cost?.losesWork == true { quit = quit.losingWork() }
                fixes.append(quit)
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
            let cost = alt.kind == .browser ? QuitCost.loses("Closes all tabs.") : SyncApps.app(bundle: b) != nil ? QuitCost.keeps(syncQuit)
                : (quitRisks[alt.name] ?? QuitCost.keeps("It'll ask to save first."))
            let quit2 = Fix(id: "quit2", title: "Quit \(alt.name) instead", consequence: "Frees \(Fmt.bytes(alt.bytes)). " + cost.words, kind: .quitApp(b))
            fixes.append(cost.losesWork ? quit2.losingWork() : quit2)
        }
        if lowDisk(s) {
            // frees disk the Mac can use as memory, and loses nothing: the advice when nothing else is
            if let b = Leftovers.buildDataFix(bytes: buildData) { var f = b; f.recommended = !fixes.contains { $0.recommended }; fixes.append(f) }
            fixes.append(freeDisk)
        }
        fixes.append(Fix(id: "wait", title: "Wait 30 minutes", consequence: "Your Mac stays slow for now.",
                         kind: .wait(now.addingTimeInterval(1800)), recommended: !fixes.contains { $0.recommended }))
        var card = Card(state: .unknown, headline: head, explanation: expl + (limitNote.map { " " + $0 } ?? ""), fixes: fixes)
        card.names = names
        return card
    }

    /// Why tight memory matters: how much the Mac is moving to its disk (or that it's using its disk at all), and, when
    /// the startup disk is nearly full, that it needs that space as extra memory.
    static func pressure(_ s: MacState) -> String {
        var t: String
        if let mb = s.swappedOutMB, mb >= movingSwapMB {
            t = "In the last 2 minutes, your Mac moved \(Fmt.bytes(UInt64(mb * 1_048_576))) of memory to its disk, which is slow."
        } else {
            t = s.swapUsedMB > 50 ? "Your Mac is using its disk as extra memory, which is slow." : "When memory runs low, your Mac slows down."
        }
        if lowDisk(s), let d = s.diskFreeBytes {
            t += " Your startup disk has only \(diskGB(d)) free, which limits how much of it your Mac can use as memory. If it runs out, apps can't save, and macOS asks you to quit some."
        }
        return t
    }

    /// Memory moved to the disk in 2 minutes that's worth saying on the card.
    static let movingSwapMB = 256.0
    /// Memory moved to the disk in 2 minutes that counts as tight memory even when macOS says normal. Not from a
    /// source: a high bar so it shows only for heavy swapping.
    public static let heavySwapMB = 1024.0
    /// Free space on the startup disk below which tight memory also mentions the disk. Not from a source: Howard
    /// Oakley advises keeping 50 GB free; macOS warns near 1 GB and purges toward about 10 to 15 GB (research node N-006).
    public static let lowDiskBytes: UInt64 = 20_000_000_000
    public static func lowDisk(_ s: MacState) -> Bool { s.diskFreeBytes.map { $0 < lowDiskBytes } ?? false }

    /// Ollama or its model runner, as the memory card groups it.
    public static func isOllama(_ g: MemGroup) -> Bool {
        ["ollama", "llama-server", "ollama_llama_server"].contains(g.name.lowercased())
    }
    /// Disk space as Finder and Storage settings count it (1 GB = 1,000,000,000 bytes).
    public static func diskGB(_ b: UInt64) -> String {
        let g = Double(b) / 1_000_000_000
        return g >= 10 ? String(format: "%.0f GB", g) : String(format: "%.1f GB", g)
    }
    /// Takes you to Storage settings, where macOS shows what takes the most space and offers ways to free it.
    static let freeDisk = Fix.openApp("disk", "Free up disk space", bundle: "/System/Applications/System Settings.app",
                                      steps: "Click General, then Storage, to see what takes the most space and what macOS can remove for you.")
}
