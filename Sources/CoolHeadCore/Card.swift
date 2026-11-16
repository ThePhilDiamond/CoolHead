import Foundation

/// Whether a busy process is doing its job, and how we know.
public enum JobState: String {
    case working      // progress advancing, or output still being written
    case waiting      // queued behind another job
    case stalled      // no progress for a long time: the only state where stopping is offered
    case unknown      // busy for a long time, with no sign either way
    case starting     // busy, but only just started
    case quiet        // not busy
}

public enum Health {
    /// Minutes without progress before a job counts as stalled (COOLHEAD_STALL_MINUTES overrides it, for testing).
    public static var stallMinutes: Double {
        Double(ProcessInfo.processInfo.environment["COOLHEAD_STALL_MINUTES"] ?? "") ?? 30
    }

    /// `busySince`: when the watcher first saw it busy; without it, the process's start time is used.
    public static func assess(_ e: Evidence, now: Date = Date(), busySince: Date? = nil) -> JobState {
        let busy = e.coresNow >= 0.25 || e.gpuBusy             // on the CPU or the graphics chip
        let ran = now.timeIntervalSince(busySince ?? e.start ?? now)
        if let l = e.lastLine?.lowercased(), l.contains("waiting"), e.coresNow < 0.1, (e.gpuShare ?? 0) < 0.1 { return .waiting }
        if let p = e.progress {
            // stalled: quiet for longer than the limit and than three of its own usual gaps between progress lines,
            // and not writing anything now. A job that reports itself done, or is still writing (saving a large
            // result, say), is working, however long ago its last progress line was.
            let limit = max(stallMinutes, 3 * (p.typicalGapMinutes ?? 0))
            let writingNow = e.bytesWrittenDuringSample > 0 || (e.lastOutput.map { now.timeIntervalSince($0) < limit * 60 } ?? false)
                && e.lastOutput != p.lineTime
            if p.fraction == 1 || writingNow { return .working }
            return now.timeIntervalSince(p.lineTime) > limit * 60 ? .stalled : .working
        }
        if e.bytesWrittenDuringSample > 0 || (e.lastOutput.map { now.timeIntervalSince($0) < 600 } ?? false) {
            return busy || ran < 600 ? .working : .quiet
        }
        if busy && ran < 20 * 60 { return .starting }
        return busy ? .unknown : .quiet
    }
}

/// One thing the user can do about a card, with what it would cause.
public struct Fix: Identifiable {
    public enum Kind: Equatable {
        case wait(Date)          // hide the card until then; it comes back if the cause is still there
        case stop                // SIGTERM, after asking; only the user's own processes
        case cooler              // background priority: slower CPU and disk access, less heat
        case lookUp(String)      // a web search for this process name only
        case quitApp(String)     // a normal quit of the app at this bundle path, so it can ask to save
        // Every option is a button (Phil, 16 November 2026: "It's incongruous and unintuitive to have a mix of buttons and
        // non-buttons. If I click something, even if it just navigates to a guide or explanation how to do the task, it
        // would be better than a non-button."). What Cool Head can't do itself, it takes you to, or shows how:
        case openApp(String, String)    // bring this app (bundle path) forward, then say these steps
        case reveal(String, String)     // show this folder in Finder, then say these steps
        case guide(String)              // show these steps under the option
        case share               // show the anonymised case report, then offer to open it as a GitHub issue
        case openPage(String, String)   // open a page of an app's own settings in that app: bundle path, address
        case pauseJob            // SIGSTOP until the Mac is plugged in; resumed then, or on request, or when Cool Head quits
        case pauseSync(String, String)  // open a sync app (bundle path, name) to pause it, with a reminder to resume
        case chromeLimit(Int?)   // set Chrome's own memory limit to this many MB (nil: remove it), as Chrome settings on this Mac
        case resume              // SIGCONT for a process something other than Cool Head paused
        case forceQuit           // SIGKILL for an app that isn't responding, after asking: what Force Quit in the Apple menu does
        case restartBrowser(String)   // a normal quit of the browser at this bundle path, then reopen it with its last session
    }
    public let id: String
    public let title: String
    public let consequence: String
    public let kind: Kind
    public var recommended = false

    /// An option that opens an app and says what to do there.
    public static func openApp(_ id: String, _ title: String, bundle: String, steps: String, recommended: Bool = false) -> Fix {
        let app = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        return Fix(id: id, title: title, consequence: "Opens \(app). \(steps)", kind: .openApp(bundle, steps), recommended: recommended)
    }

    /// An option that shows how to do something Cool Head can't do itself: `steps` appear under it when pressed.
    public static func guide(_ id: String, _ title: String, _ consequence: String, steps: String, recommended: Bool = false) -> Fix {
        Fix(id: id, title: title, consequence: consequence, kind: .guide(steps), recommended: recommended)
    }

    static let activityMonitor = "/System/Applications/Utilities/Activity Monitor.app"
}

/// What the user sees: one sentence saying what it is and whether it is fine; behind "Explore fixes", a short
/// explanation of how we know, and the options, each with its consequence, one of them recommended.
public struct Card {
    public let state: JobState
    public let headline: String
    public let explanation: String
    public let fixes: [Fix]

    public init(state: JobState, headline: String, explanation: String, fixes: [Fix]) {
        self.state = state; self.headline = headline; self.explanation = explanation
        // Waiting isn't an option in the list: each card has a clock in its corner for that (10 minutes, 30 minutes or
        // an hour, never "until it's done"). The rest in one fixed order (Phil, 15 November 2026).
        var seen = false
        let kept = fixes.filter { if case .wait = $0.kind { return false }; return true }.map { f -> Fix in
            var f = f
            if f.recommended { if seen { f.recommended = false }; seen = true }    // one recommendation at most
            return f
        }
        self.fixes = kept.enumerated().sorted { (Card.rank($0.element), $0.offset) < (Card.rank($1.element), $1.offset) }.map(\.element)
    }

    /// The order every card's options are shown in, so they read the same way everywhere: the recommended option;
    /// then options you can undo, most helpful first; then options that close or lose something, least loss first;
    /// then sharing; then notes with nothing to press.
    public static func rank(_ f: Fix) -> Int {
        if f.recommended { return 0 }
        switch f.kind {
        case .cooler, .pauseJob, .chromeLimit, .resume: return 1
        case .pauseSync: return 2
        case .openPage, .openApp, .reveal, .guide: return 2
        case .lookUp: return 3
        case .restartBrowser: return 3     // closes the browser, but its tabs come back: less loss than quitting
        case .quitApp, .forceQuit: return 4
        case .stop: return f.id == "stop" ? 5 : 4      // closing one tab or extension loses less than quitting its browser
        case .share: return 6
        case .wait: return 8
        }
    }

    public var recommended: Fix? { fixes.first { $0.recommended } }
    /// Has something to press that acts on the cause (not only advice or sharing).
    public var hasAction: Bool {
        fixes.contains { f in
            switch f.kind {
            case .cooler, .stop, .quitApp, .lookUp, .openPage, .pauseJob, .pauseSync, .chromeLimit, .resume, .forceQuit, .restartBrowser: return true
            // opening an app, showing a folder or showing how help, but don't act on the cause
            default: return false
            }
        }
    }

    /// Who the card is about, in a word or two: the project ("Photo Export"), the script, or the app.
    public static func subject(_ e: Evidence) -> String {
        // a script names the job better than its runtime (Homebrew's Python is itself an app bundle)
        if e.script != nil { return e.project ?? e.task }
        if let part = e.browserPart, let app = e.app {
            return part == .tab ? "\(app) tab" : part == .extensionPart ? "\(app) extension" : app
        }
        if let app = e.app { return app }
        return e.name
    }

    static func wait(until: Date?, now: Date, recommended: Bool) -> Fix {
        if let u = until, u > now.addingTimeInterval(120) {
            return Fix(id: "wait", title: "Wait until \(Fmt.time(u))", consequence: "It should be done by then.",
                       kind: .wait(u), recommended: recommended)
        }
        return Fix(id: "wait", title: "Wait 30 minutes", consequence: "We'll check again then.",
                   kind: .wait(now.addingTimeInterval(1800)), recommended: recommended)
    }

    static let share = Fix(id: "share", title: "Share this case", consequence: "Help us figure it out. You see everything first.", kind: .share)

    static func lookUp(_ name: String, recommended: Bool) -> Fix {
        Fix(id: "lookup", title: "Look it up", consequence: "Search the web for \u{201C}\(name)\u{201D}.", kind: .lookUp(name), recommended: recommended)
    }

    public static func make(_ e: Evidence, now: Date = Date(), busySince: Date? = nil, warm: Bool = false, gameRunning: String? = nil,
                            frontApp: String? = nil, battery: Int? = nil, syncFeed: SyncFeed? = nil) -> Card {
        let onBattery = battery != nil
        let who = subject(e)
        let since = busySince ?? e.start ?? now
        let busyFor = now.timeIntervalSince(since)
        let state = Health.assess(e, now: now, busySince: busySince)
        let atStake = now.timeIntervalSince(e.workStart ?? e.start ?? now)
        let output = e.writing.first { !Evidence.isLog($0) }.map { ($0 as NSString).lastPathComponent }
        // the graphics chip (see GPU): busy on it counts as busy, and the card says how much of it
        let gpu = e.gpuShare ?? 0
        let active = e.coresNow >= 0.25 || e.gpuBusy
        let gpuLine = e.gpuBusy ? " It's keeping the graphics chip busy, \(Fmt.share(gpu)) of it." : ""
        let gpuLed = e.gpuBusy && e.coresNow < 0.5            // here for the graphics chip, not the CPU
        let heating = e.coresNow >= 0.5 || gpu >= GPU.busyShare

        // what stopping would cost, in a few words
        func stopConsequence() -> String {
            if state == .stalled, let p = e.progress { return "Nothing since \(Fmt.time(p.lineTime)) is lost." }
            let lose = atStake >= 10 * 60 ? "You may lose up to \(Fmt.duration(atStake)) of work." : "Little work is lost."
            return lose + (output.map { " \($0) may be left unfinished." } ?? "")
        }
        // never macOS's own programs (stopping loginwindow logs you out), and never an app's main program: an app
        // should be quit, which lets it ask to save, not stopped
        let appMain = e.script == nil && (e.path.map { $0.components(separatedBy: ".app/").count == 2 && $0.contains(".app/Contents/MacOS/") } ?? false)
        // a script run by macOS's own interpreter (/usr/bin/python3) is still the person's job
        let macOSProgram = e.script == nil && (e.path.map(CaseReport.isMacOS) ?? true)
        let stoppable = e.mine && !macOSProgram && !appMain
        let stop: Fix? = stoppable ? Fix(id: "stop", title: "Stop it", consequence: stopConsequence(), kind: .stop, recommended: state == .stalled) : nil
        let cooler: Fix? = e.mine && e.coresNow >= 0.5
            ? Fix(id: "cooler", title: "Run it cooler", consequence: "Slower, but less heat. Undo any time.", kind: .cooler, recommended: false)
            : nil

        // macOS's own processes: what it is doing, and whether this has gone on longer than usual
        if let k = Pattern.match(name: e.name, path: e.path), e.progress == nil {
            let long = busyFor > k.usualHours * 3600 && busyFor >= 20 * 60
            let explanation = (long
                ? "It usually takes under \(Fmt.duration(k.usualHours * 3600)). This has gone on for \(Fmt.duration(busyFor))."
                : "Normal \(k.normal)." + (k.endsOnItsOwn ? " It stops on its own." : "")) + gpuLine
            var fixes: [Fix] = []
            if long {
                if k.whenLong == "Look it up" { fixes.append(lookUp(e.name, recommended: true)) }
                else {
                    // what the catalogue advises, as a button: open the app it's about, or Activity Monitor to find the heat
                    if k.whenLong.hasPrefix("Find what is heating") {
                        fixes.append(Fix.openApp("advice", k.whenLong, bundle: Fix.activityMonitor, steps: "Click % CPU to put the busiest first.", recommended: true))
                    } else if let b = e.appBundle {
                        fixes.append(Fix.openApp("advice", k.whenLong, bundle: b, steps: k.risk ?? "", recommended: true))
                    } else {
                        fixes.append(Fix.guide("advice", k.whenLong, k.risk ?? "", steps: k.risk ?? k.whenLong, recommended: true))
                    }
                    fixes.append(lookUp(e.name, recommended: false))
                }
                fixes.append(wait(until: nil, now: now, recommended: false))
                fixes.append(share)
            } else {
                fixes.append(wait(until: nil, now: now, recommended: true))
            }
            if let bundle = e.quittableBundle, let app = e.quittableApp, k.risk != nil, k.whenLong.hasPrefix("Quit") {
                fixes.append(Fix(id: "quit", title: "Quit \(app)", consequence: k.risk!, kind: .quitApp(bundle)))
            }
            let head = !active ? "\(k.doing). It's quiet now."
                : long ? "\(k.doing), for \(Fmt.duration(busyFor)). That's longer than usual."
                : "\(k.doing). That's normal."
            // a statement, not an option: macOS restarts its own programs
            return Card(state: !active ? .quiet : long ? .unknown : .working, headline: head,
                        explanation: explanation + (e.mine ? "" : " macOS needs it: stopping it would just restart it."), fixes: fixes)
        }

        // security, device management and VPN software: never stopped, slowed or quit (from System Sentinel's review,
        // 15 November 2026): stopping one can leave the Mac unprotected or break an employer's rules
        if let product = SecuritySoftware.product(path: e.path, name: e.name) {
            if e.coresNow < 0.25 { return Card(state: .quiet, headline: "\(product.name) is quiet now.", explanation: "", fixes: []) }
            let vpn = product.kind == .vpn
            return Card(state: .working,
                        headline: vpn ? "\(product.name) is your VPN, handling your network traffic." : "\(product.name) is security software, checking files as they're used.",
                        explanation: "Cool Head won't stop or slow it: that could leave your Mac unprotected or break your organization's rules."
                            + (vpn ? "" : " If it's busy for hours, tell whoever manages this Mac: it may be stuck scanning a big folder."),
                        fixes: [vpn ? e.appBundle.map { Fix.openApp("disconnect", "Disconnect when you don't need it", bundle: $0, steps: "Disconnect there, or from its menu bar icon.") } : nil,
                                lookUp(product.name, recommended: false)].compactMap { $0 })
        }

        // sync apps: catching up is normal, and pausing loses nothing; slowing or quitting come after
        if let sync = SyncApps.app(bundle: e.appBundle), let bundle = e.appBundle {
            if e.coresNow < 0.25 { return Card(state: .quiet, headline: "\(sync) is quiet now.", explanation: "", fixes: []) }
            // a build or job writing lots of files into a folder it syncs is the cause to fix, ahead of pausing
            // (Phil's Google Drive errors, 15 November 2026)
            return Card(state: .working, headline: "\(sync) is syncing your files.",
                        explanation: "It uploads and checks every change, and stops when it's caught up." + (warm && e.coresNow >= 0.5 ? " It's adding to the heat." : "")
                            + (syncFeed.map { " " + $0.sentence(sync) } ?? ""),
                        fixes: [syncFeed?.fix(sync, recommended: true),
                                Fix(id: "pause", title: "Pause syncing", consequence: "Opens \(sync) so you can pause it; we'll remind you to resume. Changes wait until then.",
                                    kind: .pauseSync(bundle, sync), recommended: warm || gameRunning != nil
                                        || (onBattery && (e.coresNow >= 2 || ((battery ?? 100) < 50 && e.coresNow >= 1)))),
                                e.mine && e.coresNow >= 0.5 ? Fix(id: "cooler", title: "Run it cooler", consequence: "Syncs slower. Undo any time.", kind: .cooler) : nil,
                                Fix(id: "quit", title: "Quit \(sync)", consequence: "Stops syncing until you open it again.", kind: .quitApp(bundle))].compactMap { $0 })
        }

        // Chrome and other Chromium browsers, without quitting them (Phil, 15 November 2026: "Chrome is one of the
        // biggest causes, so we should look into if there are ways we can improve performance without killing it when a
        // user is using it"). A process can be told apart as a tab, an extension or the graphics process, but not which
        // tab: only the browser's Task Manager knows that.
        if let part = e.browserPart, let app = e.app, let bundle = e.appBundle {
            let inFront = frontApp == bundle                 // you're using the browser: the busy tab may be the one you're on
            let what = part == .tab ? "One tab" : part == .extensionPart ? "One extension" : "Its graphics process"
            let explanation = (gpuLed ? "\(what) has kept the graphics chip busy for \(Fmt.duration(busyFor)), \(Fmt.share(gpu)) of it."
                               : "\(what) has used about \(Fmt.cores(e.coresNow)) for \(Fmt.duration(busyFor))." + gpuLine)
                + (part == .graphics ? " Usually video or animation." : " Only \(app) knows which.")
                + (warm && heating ? " It's adding to the heat." : "")
            let canCool = e.mine && e.coresNow >= 0.5 && part != .graphics     // slowing graphics would slow all of it
            let page = { (url: String, title: String, why: String, rec: Bool) in
                Fix(id: "page", title: title, consequence: why, kind: .openPage(bundle, url), recommended: rec) }
            let find = Fix.openApp("find", part == .extensionPart ? "Find the busy extension" : "Find the busy tab", bundle: bundle, steps: "Then Window ▸ Task Manager, and sort by CPU.")
            let quit = Fix(id: "quit", title: "Quit \(app)", consequence: "Closes all tabs.", kind: .quitApp(bundle))
            var fixes: [Fix?]
            switch part {
            case .tab:
                fixes = [canCool ? Fix(id: "cooler", title: "Run this tab cooler", consequence: "Only this tab slows. Undo any time.", kind: .cooler, recommended: !inFront) : nil,
                         page("chrome://settings/performance", "Turn on Energy Saver", "Takes you to \(app)'s Performance settings. Less background work, lower frame rates.", inFront || !canCool),
                         find,
                         e.mine ? Fix(id: "closetab", title: "Close just that tab", consequence: "It shows a crash page; Reload brings it back. Anything typed in it is lost.", kind: .stop) : nil,
                         quit]
            case .extensionPart:
                fixes = [page("chrome://extensions", "Turn off the extension", "Takes you to \(app)'s extensions page. Switch off the one you don't need.", true),
                         canCool ? Fix(id: "cooler", title: "Run it cooler", consequence: "Only this extension slows. Undo any time.", kind: .cooler) : nil,
                         find,
                         e.mine ? Fix(id: "stopext", title: "Stop the extension", consequence: "\(app) says it crashed. Reload it from the extensions page.", kind: .stop) : nil,
                         quit]
            case .graphics:
                fixes = [page("chrome://settings/performance", "Turn on Energy Saver", "Takes you to \(app)'s Performance settings. Lower frame rates, less heat.", true),
                         find, quit]
            }
            let head = part == .tab ? "A \(app) tab is working hard." : part == .extensionPart ? "A \(app) extension is working hard."
                : "\(app) is drawing a lot: video or animation in a tab."
            return Card(state: !active ? .quiet : busyFor > 20 * 60 ? .unknown : .starting,
                        headline: head, explanation: explanation, fixes: fixes.compactMap { $0 })
        }

        // web pages: the busy process is a tab or extension, and only the browser knows which
        // WebKit's graphics process draws web pages for Safari, and for any other app that shows them
        let webkitGPU = e.name == "com.apple.WebKit.GPU" || (e.path?.contains("com.apple.WebKit.GPU") ?? false)
        let webkit = webkitGPU || e.name == "com.apple.WebKit.WebContent" || (e.path?.contains("com.apple.WebKit.WebContent") ?? false)
        if let app = webkit ? "Safari" : e.app, webkit || e.name.contains("Renderer") || e.name.contains("Web Content") || e.name.contains("(Plugin)") {
            let tm = app.contains("Safari") ? "Window ▸ Activity" : "Window ▸ Task Manager"
            let used = gpuLed ? "has kept the graphics chip busy for \(Fmt.duration(busyFor)), \(Fmt.share(gpu)) of it."
                : "has used about \(Fmt.cores(e.coresNow)) for \(Fmt.duration(busyFor))." + gpuLine
            return Card(state: !active ? .quiet : busyFor > 20 * 60 ? .unknown : .starting,
                        headline: webkitGPU ? "A web page is drawing a lot: video or animation." : "A \(app) tab is working hard.",
                        explanation: webkitGPU ? "The process that draws web pages \(used) Usually a Safari tab; other apps that show web pages have one too."
                            : "One tab or extension \(used) Only \(app) knows which.",
                        fixes: [(e.outerBundle ?? (webkit ? "/Applications/Safari.app" : nil)).map { Fix.openApp("find", "Find the busy tab", bundle: $0, steps: "Then \(tm), and sort by CPU.", recommended: true) }
                                    ?? Fix.guide("find", "Find the busy tab", "In \(app): \(tm), sort by CPU.", steps: "In \(app), choose \(tm), then sort by CPU. The busiest tab is at the top.", recommended: true),
                                (e.outerBundle ?? (webkit ? "/Applications/Safari.app" : nil)).map { Fix(id: "quit", title: "Quit \(app)", consequence: "Closes all tabs.", kind: .quitApp($0)) },
                                lookUp(e.name, recommended: false),
                                wait(until: nil, now: now, recommended: false)].compactMap { $0 })
        }

        // games are protected (Phil, 15 November 2026: "if we "run it cooler" with a game, couldn't it adversely impact
        // performance? We may wish to protect games as a class we know will usually be busy and suggest killing other
        // tasks first to improve game performance"): busy is what a game does, so it's calm and never slowed down;
        // when the Mac is warm, lower settings is the fix that keeps play smooth
        if let game = e.gameBundle {
            let name = ((game as NSString).lastPathComponent as NSString).deletingPathExtension
            if !active { return Card(state: .quiet, headline: "\(name) is quiet now.", explanation: "", fixes: []) }
            return Card(state: .working, headline: "\(name) is a game. Games keep your Mac busy while they run.",
                        explanation: "That's normal while you play." + gpuLine + (warm ? " It's adding to the heat." : ""),
                        fixes: [Fix.openApp("settings", "Lower its graphics settings", bundle: game, steps: "In its settings, lower quality or frame rate. Less heat, still smooth.", recommended: warm),
                                Fix(id: "quit", title: "Quit \(name)", consequence: "Save your game first. Unsaved progress may be lost.", kind: .quitApp(game))])
        }

        // while a game is being played, other busy work is the thing to slow, so the game runs smoothly
        let forGame = gameRunning != nil && cooler != nil
        // on battery, with Save Battery When Unplugged on: a heavy job (a script or command-line tool, never an app)
        // can be frozen until the Mac is plugged in. Nothing is lost, unlike stopping it (Phil's rule: stopping is
        // recommended only when a job has stalled).
        let pausable = e.mine && (e.script != nil || (e.appBundle == nil && !(e.path.map(CaseReport.isMacOS) ?? true)))
        // only the really hungry or long-running while the battery is healthy; any steady load once it's under half
        // (Phil, 15 November 2026: "only be aggressive to really hungry /extended processes or when battery is below 50%")
        let hungry = (e.coresNow >= 2 && busyFor >= 600) || (e.coresNow >= 1 && busyFor >= 1800)
        let drains = onBattery && pausable && state != .stalled && e.coresNow >= 1 && busyFor >= 600
            && (hungry || (battery ?? 100) < 50)
        let pauseFix: Fix? = drains ? Fix(id: "pausejob", title: "Pause until you plug in",
                                          consequence: "Frozen, nothing lost; it carries on when you plug in. A download may time out.",
                                          kind: .pauseJob, recommended: true) : nil
        let cool = cooler.map { c -> Fix in
            var c = c; c.recommended = warm || forGame
            if let g = gameRunning { c = Fix(id: c.id, title: c.title, consequence: "Leaves more power for \(g). Undo any time.", kind: c.kind, recommended: c.recommended) }
            return c
        }
        // an app here for the graphics chip: what lets the chip rest, and quitting it (slowing it wouldn't help: background
        // priority slows its CPU work, not its drawing)
        let gpuApp = gpuLed ? e.quittableApp : nil
        let gpuQuit = gpuApp.flatMap { app in e.quittableBundle.map {
            Fix(id: "quit", title: "Quit \(app)", consequence: "Lets the graphics chip rest. It may ask you to save first.", kind: .quitApp($0)) } }
        // while the Mac is warm, a busy job says it is part of why
        let heat = gpuLine + (gpuApp != nil ? " Pausing or closing a video, animation or 3D view in it lets the chip rest." : "")
            + (warm && heating ? " It's adding to the heat." : "") + (forGame || (gameRunning != nil && gpuLed) ? " It's competing with \(gameRunning!)." : "")
            + (drains ? " It's draining your battery." : "")
        switch state {
        case .working:
            if let p = e.progress {
                var head = "\(who) is " + (p.fraction.map { "\(Fmt.percent($0)) done." } ?? "making progress.")
                if let fin = p.finish { head += fin > now ? " Ready around \(Fmt.time(fin))." : " Almost done." }
                return Card(state: state, headline: head, explanation: "Its log says \u{201C}\(p.line)\u{201D}." + heat,
                            fixes: [pauseFix, wait(until: p.finish, now: now, recommended: !warm || cooler == nil), cool, gpuQuit, stop].compactMap { $0 })
            }
            return Card(state: state, headline: "\(who) is busy and still saving its work.",
                        explanation: "It doesn't say how far along it is." + heat,
                        fixes: [pauseFix, wait(until: nil, now: now, recommended: !warm || cooler == nil), cool, gpuQuit, stop].compactMap { $0 })
        case .waiting:
            return Card(state: state, headline: "\(who) is waiting for another job.",
                        explanation: "It isn't using your Mac's power while it waits.",
                        fixes: [wait(until: nil, now: now, recommended: true), stop].compactMap { $0 })
        case .stalled:
            let at = e.progress.map { Fmt.time($0.lineTime) } ?? "a while"
            return Card(state: state, headline: "\(who) hasn't moved since \(at). It looks stuck.",
                        explanation: "No new progress for \(Fmt.duration(now.timeIntervalSince(e.progress?.lineTime ?? now))).",
                        fixes: [stop ?? lookUp(e.name, recommended: true), wait(until: nil, now: now, recommended: false), share])
        case .unknown:
            return Card(state: state, headline: "\(who) has been busy for \(Fmt.duration(busyFor)). We can't tell why.",
                        explanation: "It isn't saying what it's doing." + heat,
                        fixes: [pauseFix, lookUp(e.name, recommended: !forGame), wait(until: nil, now: now, recommended: false),
                                forGame ? cool : cooler, gpuQuit,
                                stop.map { var f = $0; f = Fix(id: f.id, title: f.title, consequence: "Only if you know what it is. " + f.consequence, kind: f.kind); return f },
                                share].compactMap { $0 })
        case .starting:
            return Card(state: state, headline: "\(who) just started. Give it a minute.", explanation: "Started at \(Fmt.time(e.start ?? now))." + heat,
                        fixes: [pauseFix, wait(until: nil, now: now, recommended: true), forGame ? cool : cooler, gpuQuit, stop].compactMap { $0 })
        case .quiet:
            return Card(state: state, headline: "\(who) is quiet now.", explanation: "", fixes: [])
        }
    }
}

/// Formats in Phil's style: 4:50pm, 3 hours 20 minutes.
public enum Fmt {
    public static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.component(.minute, from: d) == 0 ? "ha" : "h:mma"
        let s = f.string(from: d).lowercased()
        let cal = Calendar.current
        if cal.isDateInToday(d) { return s }
        if cal.isDateInTomorrow(d) { return "\(s) tomorrow" }
        if cal.isDateInYesterday(d) { return "\(s) yesterday" }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "d MMMM"
        return "\(s) on \(day.string(from: d))"
    }

    public static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 1 { return "under a minute" }
        if m < 60 { return m == 1 ? "1 minute" : "\(m) minutes" }
        let h = m / 60, r = m % 60
        let hs = h == 1 ? "1 hour" : "\(h) hours"
        return r == 0 ? hs : "\(hs) \(r) minute\(r == 1 ? "" : "s")"
    }

    /// A clock time alone, for chart labels: 11:59pm.
    public static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.component(.minute, from: d) == 0 ? "ha" : "h:mma"
        return f.string(from: d).lowercased()
    }

    public static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded(.down)))%" }

    /// A rough share, to the nearest 5%: "about 70%", or "under 5%".
    public static func share(_ f: Double) -> String {
        let p = Int((f * 20).rounded()) * 5
        return p < 5 ? "under 5%" : "about \(min(100, p))%"
    }

    public static func cores(_ c: Double) -> String {
        if c < 0.95 { return "\(Int((c * 100).rounded()))% of one core" }
        let r = (c * 2).rounded() / 2
        let s = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
        return r == 1 ? "1 core" : "\(s) cores"
    }

    public static func bytes(_ b: UInt64) -> String {
        let g = Double(b) / 1_073_741_824
        return g >= 1 ? String(format: "%.1f GB", g) : "\(Int(Double(b) / 1_048_576)) MB"
    }
}
