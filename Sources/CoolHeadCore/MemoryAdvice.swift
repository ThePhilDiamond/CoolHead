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
    /// loses something reopening can't bring back: work in progress, a call, what's running. Only those are Caution,
    /// which is kept for real risk: unknown or irreversible consequences. Quitting an app like Slack isn't risky.
    struct QuitCost {
        let words: String
        let losesWork: Bool
        static func keeps(_ w: String) -> QuitCost { QuitCost(words: w, losesWork: false) }
        static func loses(_ w: String) -> QuitCost { QuitCost(words: w, losesWork: true) }
    }
    static let quitRisks: [String: QuitCost] = [
        "Docker": .loses("This stops all containers."),
        "OrbStack": .loses("This stops all containers and machines."),
        "Parallels Desktop": .loses("This shuts down the virtual machine. Save your work inside it first."),
        "UTM": .loses("This shuts down the virtual machine. Save your work inside it first."),
        "VMware Fusion": .loses("This shuts down the virtual machine. Save your work inside it first."),
        "Xcode": .loses("This stops builds and simulators."),
        "Final Cut Pro": .loses("This stops renders and exports."),
        "Adobe Premiere Pro": .loses("This stops renders and exports."),
        "DaVinci Resolve": .loses("This stops renders and exports."),
        "Logic Pro": .loses("This stops bounces. It asks you to save your work first."),
        "Slack": .keeps("This stops new messages until you open it again."),
        "Microsoft Teams": .loses("This ends your calls and stops new messages until you open it again."),
        "zoom.us": .loses("This ends your meeting."),
        "Claude": .loses("This stops what Claude does now."),
        "ChatGPT": .loses("This ends the conversation in progress."),
        "Terminal": .loses("This stops what runs in it."),
        "iTerm": .loses("This stops what runs in it."),
        "Warp": .loses("This stops what runs in it."),
        "Visual Studio Code": .loses("This stops what runs in it."),
        "Cursor": .loses("This stops what runs in it."),
        "Spotify": .keeps("This stops the music."),
        "Music": .keeps("This stops the music."),
    ]

    /// The same costs, as clauses for the decision record ("We recommend … but every container stops"), one per app;
    /// the selftest checks every app in `quitRisks` has one.
    static let quitCosts: [String: String] = [
        "Docker": "every container stops",
        "OrbStack": "every container and machine stops",
        "Parallels Desktop": "the virtual machine shuts down, so save inside it first",
        "UTM": "the virtual machine shuts down, so save inside it first",
        "VMware Fusion": "the virtual machine shuts down, so save inside it first",
        "Xcode": "builds and simulators stop",
        "Final Cut Pro": "renders and exports stop",
        "Adobe Premiere Pro": "renders and exports stop",
        "DaVinci Resolve": "renders and exports stop",
        "Logic Pro": "bounces stop, though Logic Pro asks to save",
        "Slack": "no messages arrive until you reopen it",
        "Microsoft Teams": "you leave any call, and no messages arrive until you reopen it",
        "zoom.us": "you leave your meeting",
        "Claude": "whatever Claude is doing stops",
        "ChatGPT": "the conversation in progress ends",
        "Terminal": "whatever is running in it stops",
        "iTerm": "whatever is running in it stops",
        "Warp": "whatever is running in it stops",
        "Visual Studio Code": "whatever is running in it stops",
        "Cursor": "whatever is running in it stops",
        "Spotify": "the music stops",
        "Music": "the music stops",
    ]

    /// What quitting an app costs, as a clause; nil for an app with no known cost beyond asking about unsaved work.
    public static func quitCost(_ app: String) -> String? { quitCosts[app] }

    /// What quitting a sync app costs: nothing is lost; it stops syncing and catches up when it's opened again.
    static let syncQuit = "This stops syncing until you open it again. Then it syncs what it missed. Nothing is lost."

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
    /// `leak`: the biggest app's memory has kept growing with the same windows open (see Leaks). `models`: what Ollama
    /// has loaded, when it is among the biggest (see Leftovers); `buildData`: the size of Xcode's build data, when the
    /// startup disk is nearly full.
    public static func card(_ groups: [MemGroup], mac s: MacState, now: Date = Date(), context: MemoryContext = MemoryContext(),
                            leak: Leaks.Leak? = nil, models: [Leftovers.Model]? = nil, buildData: UInt64? = nil, tabMemoryOn: Bool? = nil) -> Card {
        let verdict: CardTemplate.Verdict = s.memoryPressure == "critical" ? .veryLowOnMemory : .lowOnMemory
        guard let top = groups.first else {
            return Card(state: .unknown, CardTemplate("Apps and programs", .words(s.memoryPressure == "critical" ? "are using all of your Mac's memory" : "are using almost all of your Mac's memory"), nil,
                                                      evidence: [pressure(s)]),
                        fixes: [Fix.openApp("quitunused", "Quit apps you are not using", bundle: Fix.activityMonitor, steps: "Click Memory to see which use the most. Each app asks you to save before it quits.", recommended: true).fixingTheCause()]
                            + (lowDisk(s) ? [Leftovers.buildDataFix(bytes: buildData).map { var f = $0; f.recommended = false; return f }, freeDisk].compactMap { $0 } : []))
        }
        let size = Fmt.bytes(top.bytes)
        // No calm card when macOS says memory is short, whoever uses the most. One existed for Chrome at warning with nothing
        // moved to disk ("your Mac is keeping up"), but a Mac slowed badly in exactly that state on 23 November 2026: macOS
        // at warning for 16 minutes, Chrome the biggest, nothing moved to disk, and the card green. Moving memory to disk
        // isn't the only way memory slows a Mac, so its absence doesn't show the Mac is coping. MemoryGate still decides
        // what acts by itself (the extension's Auto); a person reading the card decides for themself.
        // how often memory has slowed this Mac this week (see PressureHistory): a pattern is a reason to act now rather than wait
        var weekNote: String? = nil
        if top.name == "Google Chrome", let w = context.week, w.count >= 2 {
            weekNote = "Full memory slowed your Mac \(w.count) times this week, for " + (w.minutes >= 1 ? "about \(Fmt.duration(Double(w.minutes) * 60))" : "less than a minute") + " in total, so it will probably happen again."
        }
        // the three biggest, named so they can be told apart (see Naming)
        let shown = Array(groups.prefix(3))
        let names = Naming.distinct(shown.map(\.named))
        let head = CardTemplate(names[0], .words("uses the most, \(size)"), verdict, verdictFirst: true)
        // the next biggest, by name, so the card shows where the rest of the memory is (the biggest is in the headline)
        let next = zip(shown.dropFirst(), names.dropFirst()).map { "\($1) (\(Fmt.bytes($0.bytes)))" }
        // the next biggest go in Nerdy stuff, not the text: the options already name the second, and a shorter card is
        // easier to read and less intimidating to someone who isn't technical
        let expl = pressure(s)
        let also = next.isEmpty ? [] : ["Also using a lot: \(Fmt.list(next))"]
        var fixes: [Fix] = []
        // the biggest app has been leaking: quitting and reopening it gives the memory back, so that's the advice
        var leaking: (reading: CardTemplate.Reading, sentence: String, fix: Fix)? = nil
        if let l = leak, top.kind == .app, let b = top.bundle {
            leaking = Leaks.addition(l, app: top.name, bundle: b, now: now, losesWork: quitRisks[top.name]?.losesWork == true)
            fixes.append(leaking!.fix)
        }
        // a local AI model kept loaded after its last use: unloading it frees its memory and loses nothing, so when Ollama
        // is the biggest it's the recommendation (see Leftovers)
        if let m = models, shown.contains(where: { isOllama($0) }), let unload = Leftovers.unloadFix(m, recommended: isOllama(top), freed: !isOllama(top)) {
            fixes.append(unload)
        }

        switch top.kind {
        case .browser:
            let steps = [TaskManager.open(top.name), TaskManager.sort(by: "Memory", so: "the tab using the most"), "Close the tabs near the top that you do not need."]
            fixes.append((top.bundle.map { Fix.openApp("tabs", "Close \(top.name)'s heaviest tabs", bundle: $0, steps: steps.joined(separator: " "), recommended: true) }
                         ?? Fix.guide("tabs", "Close \(top.name)'s heaviest tabs", "This shows how to find and close the tabs that use the most memory in \(top.name).",
                                      steps: ["Open \(top.name)."] + steps, recommended: true)).fixingTheCause())
            if top.name == "Google Chrome" {
                if let b = top.bundle {
                    // Memory Saver: nothing once it's at Maximum; Cool Head sets Maximum itself when it's worth it (see
                    // ChromeMemorySaver.shouldOffer), as part of a restart, since Chrome must be closed to change it;
                    // otherwise Chrome's own settings, as before
                    if context.memorySaver?.atMaximum == true {
                    } else if context.offerSaverMaximum {
                        fixes.append(Fix(id: "saver-max", title: "Set Memory Saver to Maximum",
                                         consequence: "This restarts Chrome, keeps your tabs, and makes Maximum your own setting. After that, tabs you do not use for 2 hours unload, and reload when you click them. It does not help right now. Incognito windows, unsent typing, and downloads do not open again.",
                                         kind: .restartBrowser(b)))
                    } else {
                        fixes.append(Fix(id: "saver", title: "Turn on Memory Saver", consequence: "This opens Chrome's Performance settings. With Memory Saver on, tabs you do not use sleep, and reload when you click them.", kind: .openPage(b, "chrome://settings/performance")))
                    }
                    // Chrome names each tab and its memory, which Cool Head can't, so the person can see which tabs are
                    // the big ones; not offered once it's on (see ChromeHoverMemory)
                    if (tabMemoryOn ?? ChromeHoverMemory.read()) != true {
                        fixes.append(Fix(id: "tabmemory", title: "Show each tab's memory", consequence: "This opens Chrome's Appearance settings. Turn on \(Fmt.ui("Show memory usage on tab hover preview card")), then point at a tab to see how much memory it uses.", kind: .openPage(b, "chrome://settings/appearance")))
                    }
                    // tab groups hold whole projects of hidden tabs: hiding a group gives their memory back and keeps the group
                    // to open again (Chrome 158's menu: "Hide group"; "Close group" and "Delete group" are beside it)
                    // extensions hold memory that unloading tabs never reaches (see ChromeParts): Chrome's Task Manager names each
                    if let parts = context.chrome, parts.extensionBytes >= ChromeParts.extensionsWorthSaying {
                        fixes.append(Fix.openApp("extensions", "Turn off extensions you do not use", bundle: b,
                                                 steps: [parts.extensionSentence ?? "", TaskManager.open("Google Chrome"), TaskManager.sort(by: "Memory", so: "what uses the most"),
                                                         "Extensions are the rows that start with \(Fmt.ui("Extension:")). Turn off the ones you do not use in Chrome's Extensions settings (type \(Fmt.ui("chrome://extensions")) in the address bar)."].joined(separator: " ")))
                    }
                    if let parts = context.chrome, parts.markWorks, parts.hiddenBytes >= ChromeParts.worthGroups {
                        fixes.append(Fix.guide("groups", "Hide tab groups you are not using",
                                               "This closes their tabs and frees their memory. Chrome keeps each group under Tab groups in its menu, so you can open it again.",
                                               steps: ["In Chrome, right-click the name of a tab group you are not using.", "Choose Hide group."]))
                    }
                }
            } else if top.name == "Microsoft Edge" {
                if let b = top.bundle {
                    fixes.append(Fix(id: "saver", title: "Turn on sleeping tabs", consequence: "This opens Edge's System and performance settings. With sleeping tabs on, tabs you do not use sleep, and reload when you click them.", kind: .openPage(b, "edge://settings/system")))
                }
            }
            if let b = top.bundle {
                fixes.append(Fix(id: "quit", title: "Quit \(top.name)", consequence: "This closes all its tabs.", kind: .quitApp(b)).losingWork())
            }
        case .app:
            if let b = top.bundle, let sync = SyncApps.app(bundle: b) {
                // a sync app: quitting frees its memory and loses nothing, unlike an app with unsaved work; pausing
                // keeps it open, so it stops it working harder but doesn't give its memory back
                fixes.append(Fix(id: "quit", title: "Quit \(sync)", consequence: syncQuit, kind: .quitApp(b), recommended: true))
                fixes.append(Fix(id: "pause", title: "Pause syncing", consequence: "This opens \(sync) so you can pause it, and Cool Head reminds you to start it again. It stays open, so its memory is not freed.",
                                 kind: .pauseSync(b, sync)))
            } else if let b = top.bundle, SecuritySoftware.product(path: b + "/", name: top.name) == nil {   // never security software
                // recommended when quitting loses nothing reopening can't bring back (Slack, or an app that asks to save)
                let cost = quitRisks[top.name]
                var quit = Fix(id: "quit", title: "Quit \(top.name)", consequence: cost?.words ?? CardTemplate.Loss.asksToSave.sentence,
                               kind: .quitApp(b), recommended: cost?.losesWork != true)
                if cost?.losesWork == true { quit = quit.losingWork() }
                fixes.append(quit)
            }
        case .job:
            if let e = top.evidence, Card.make(e, now: now).fixes.contains(where: { $0.kind == .stop }) {
                // the cost in full, from the job's own Situation: the job card may say "in that time" after its own
                // headline's busy time, which this card's headline doesn't give
                let s = Situation(e, now: now)
                let cost = (s.state == .unknown ? JobCard.onlyIfKnown : "") + (s.stop?.consequence ?? "")
                fixes.append(Fix(id: "stop", title: "Stop it", consequence: cost, kind: .stop, recommended: false))
            }
        case .macOS, .other:
            fixes.append(Fix(id: "lookup", title: "Search the web", consequence: "This searches for \u{201C}\(top.name)\u{201D} in your browser.", kind: .lookUp(top.name)))
        }
        // Chrome among the biggest but not the biggest, with Cool Head for Chrome linked: sleeping the tabs you aren't
        // looking at gives back some of Chrome's memory and closes nothing, so it comes before Restart and Quit, and is the
        // recommendation when nothing else is. (When Chrome is the biggest, the extension's options replace Chrome's own, below.)
        let chromeBelowTop = top.name != "Google Chrome" && shown.dropFirst().contains { $0.name == "Google Chrome" && $0.kind == .browser && $0.bundle != nil }
        if chromeBelowTop, context.companion == .connected {
            fixes.append(sleepChromeTabs(context, chrome: true, recommended: !fixes.contains { $0.recommended }))
        }
        // a Chromium browser among the biggest: restarting it frees the memory it has built up, and its tabs come back
        // (see BrowserRestart); before Quit, since it loses less, and never recommended, since it closes the browser
        // you may be using and doesn't bring back private windows, unsent form text or downloads
        // For Chrome, what Cool Head reads of its parts (see ChromeParts): when its own program or graphics process has grown,
        // only a restart gives that back, so it's recommended; when it has been open for days, the option says so.
        var partsNote: String? = nil
        if let r = groups.prefix(3).first(where: { $0.kind == .browser && BrowserRestart.browsers.contains($0.name) && $0.bundle != nil }), let b = r.bundle {
            let parts = r.name == "Google Chrome" ? context.chrome : nil
            let days = parts?.openFor(now: now).flatMap { $0 >= ChromeParts.openLong ? Int($0 / 86400) : nil }
            let builtUp = days.map { "to free memory it built up in the last \($0) days" } ?? "to free memory it built up"
            var restart = Fix(id: "restart", title: "Restart \(r.name) and keep your tabs",
                              consequence: "This closes and opens it again, \(builtUp). Your tabs open again. \(BrowserRestart.privateWindows(r.name).prefix(1).uppercased() + BrowserRestart.privateWindows(r.name).dropFirst()), unsent typing, and downloads in progress do not.",
                              kind: .restartBrowser(b))
            if let g = parts?.grownPart {
                restart.recommended = true
                // closing tabs still fixes the cause, so it stays, shown as that rather than recommended
                if let i = fixes.firstIndex(where: { $0.id == "tabs" }) { fixes[i].recommended = false }
                partsNote = "\(g.name) grew to \(Fmt.bytes(g.bytes)). Only a restart frees that, not closing tabs."
            }
            fixes.append(restart)
        }
        // the next largest app that can be quit, as a second way to free memory
        if let alt = groups.dropFirst().first(where: { ($0.kind == .app || $0.kind == .browser) && $0.bundle != nil
                                                        && SecuritySoftware.product(path: $0.bundle! + "/", name: $0.name) == nil }), let b = alt.bundle {
            let cost = alt.kind == .browser ? QuitCost.loses("This closes all its tabs.") : SyncApps.app(bundle: b) != nil ? QuitCost.keeps(syncQuit)
                : (quitRisks[alt.name] ?? QuitCost.keeps(CardTemplate.Loss.asksToSave.sentence))
            let quit2 = Fix(id: "quit2", title: "Quit \(alt.name) instead to free \(Fmt.bytes(alt.bytes))", consequence: cost.words, kind: .quitApp(b))
            fixes.append(cost.losesWork ? quit2.losingWork() : quit2)
        }
        if lowDisk(s) {
            // frees disk the Mac can use as memory, and loses nothing: the advice when nothing else is
            if let b = Leftovers.buildDataFix(bytes: buildData) { var f = b; f.recommended = !fixes.contains { $0.recommended }; fixes.append(f) }
            fixes.append(freeDisk)
        }
        fixes.append(Fix(id: "wait", title: "Wait 30 minutes", consequence: "Your Mac stays slow for now.",
                         kind: .wait(now.addingTimeInterval(1800)), recommended: !fixes.contains { $0.recommended }))
        // a leak: the growth and the verdict lead, with the evidence and advice alone, and a plain quit of the same app isn't offered too,
        // so the choice is easy
        if leaking != nil { fixes.removeAll { $0.id == "quit" } }
        // Cool Head for Chrome connected: the recommendation to close Chrome's heaviest tabs becomes one click, and the
        // tabs it protects stay awake. An extension can't see each tab's memory, so "heaviest" becomes the tabs
        // you aren't looking at; the extension's own count says how many. Not connected, and memory has slowed the
        // Mac twice this week: it's offered.
        if top.name == "Google Chrome", top.bundle != nil {
            if context.companion == .connected {
                let swaps: [String: Fix] = [
                    "tabs": sleepChromeTabs(context, chrome: false, recommended: true),
                    "extensions": Fix(id: "extensions", title: "Turn off extensions you do not use",
                                      consequence: "This opens a list of your extensions in Cool Head for Chrome, each with a switch.", kind: .chromeCompanion("openExtensionsList")),
                    "groups": Fix(id: "groups", title: "Hide tab groups you are not using",
                                  consequence: "This keeps each group under Tab groups in the Chrome menu, so you can open it again.", kind: .chromeCompanion("hideUnusedGroups"))]
                // a count of 0: nothing to sleep, so it isn't the recommendation (sleepChromeTabs)
                fixes = fixes.map { f in swaps[f.id].map { var n = $0; n.recommended = f.recommended && !(n.id == "sleep" && context.tabsToSleep == 0); return n } ?? f }
                fixes.append(Fix(id: "duplicates", title: "Close duplicate tabs", consequence: "This keeps the one you used last of each.", kind: .chromeCompanion("closeDuplicates")))
            }
        }
        // Not linked, and memory has slowed the Mac twice this week: the extension is offered whenever Chrome is among the biggest.
        if top.name == "Google Chrome" ? top.bundle != nil : chromeBelowTop, context.companion == .notInstalled, (context.week?.count ?? 0) >= 2 {
            fixes.append(Fix(id: "companion", title: "Get \(ChromeCompanion.name)",
                             consequence: "This links Cool Head to Chrome and shows how to add the extension. " + ChromeCompanion.pitch + " It is free.",
                             kind: .chromeCompanion("setup")))
        }
        // a leak: the growth is the reading and the leak the verdict, with the evidence alone; otherwise who uses the most,
        // and the verdict on memory (docs/BRAND.md, Card template)
        let template = leaking.map { CardTemplate(top.name, $0.reading, .probablyLeaks, evidence: [$0.sentence], effect: [s.memoryPressure == "critical" ? "Your Mac's memory is now full." : "Your Mac's memory is now almost full."]) }
            ?? CardTemplate(head.subject, head.reading, head.verdict,
                            evidence: [expl, top.name == "Google Chrome" && context.companion != .connected ? context.chrome?.hiddenSentence : nil, partsNote].compactMap { $0 },
                            effect: [weekNote].compactMap { $0 }, verdictFirst: true)
        var card = Card(state: .unknown, template, fixes: fixes)
        card.names = leaking != nil ? [top.name] : names
        card.facts = also + (context.chrome?.facts ?? []) + card.facts
        return card
    }

    /// Cool Head for Chrome's one click for Chrome's memory: the tabs out of sight sleep. The title carries the
    /// extension's own count (it leaves out the tabs it protects), so the figure is said once, where it's seen first
    /// (docs/BRAND.md, Voice). `chrome`: say "Chrome tabs", when the card is about another app. Never an amount of memory,
    /// which can't be known beforehand (memory already compressed or on the disk, protected tabs among those out of
    /// sight): afterwards the card says what Chrome gave back (ChromeParts.gaveBack).
    /// With a count of 0 (every tab out of sight already asleep or kept awake) it says so, isn't recommended, is tagged
    /// Tells you more, and is held back from the one-click rule and the next recommendation.
    static func sleepChromeTabs(_ context: MemoryContext, chrome: Bool, recommended: Bool) -> Fix {
        let n = context.tabsToSleep ?? 0
        let tabs = (chrome ? "Chrome " : "") + (n == 1 ? "tab" : "tabs")
        let what = context.tabsToSleep == 0
            ? "This finds no tab to sleep now. The tabs out of sight are already asleep or kept awake, like calls, sound, and unsent typing."
            : (n == 1 ? "This keeps it in the tab bar, and it reloads when you click it." : "This keeps them in the tab bar, and each reloads when you click it.")
                + " Tabs and sites you keep, calls, sound, and unsent typing stay awake."
        var f = Fix(id: "sleep", title: "Sleep " + (n > 0 ? "\(n) " : "") + tabs + " you are not looking at",
                    consequence: what, kind: .chromeCompanion("sleepHidden"), recommended: recommended && context.tabsToSleep != 0)
        // nothing to sleep: it frees nothing, so it only tells you that, and nothing puts it forward
        if context.tabsToSleep == 0 { f.resultOverride = .informs; f.holdBack = true }
        return f
    }

    /// Why tight memory matters: how much the Mac is moving to its disk (or that it's using its disk at all), and, when
    /// the startup disk is nearly full, that it needs that space as extra memory.
    static func pressure(_ s: MacState) -> String {
        var t: String
        if let mb = s.swappedOutMB, mb >= movingSwapMB {
            t = "Your Mac moved \(Fmt.bytes(UInt64(mb * 1_048_576))) from memory to storage in the last 2 minutes, which is slow."
        } else {
            t = s.swapUsedMB > 50 ? "Your Mac uses storage as extra memory, which is slow." : "When memory is full, your Mac gets slower."
        }
        if lowDisk(s), let d = s.diskFreeBytes {
            t += " Your storage is also nearly full, with \(diskGB(d)) free, which leaves less room for that."
        }
        // what memory and storage are is said in the terms footer under the cards (CardTemplate.terms), not here
        return t
    }

    /// Memory moved to the disk in 2 minutes that's worth saying on the card.
    static let movingSwapMB = 256.0
    /// Memory moved to the disk in 2 minutes that counts as tight memory even when macOS says normal. Not from a
    /// source: a high bar so it shows only for heavy swapping.
    public static let heavySwapMB = 1024.0
    /// Free space on the startup disk below which tight memory also mentions the disk. Not from a source: Howard
    /// Oakley advises keeping 50 GB free; macOS warns near 1 GB and purges toward about 10 to 15 GB.
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
    static let freeDisk = Fix.openApp("disk", "Make room in storage", bundle: "/System/Applications/System Settings.app",
                                      steps: "Click General, then Storage, to see what uses the most space and what macOS can remove for you.")
}
