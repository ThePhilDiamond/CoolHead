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
        let busy = e.coresNow >= 0.25
        let ran = now.timeIntervalSince(busySince ?? e.start ?? now)
        if let l = e.lastLine?.lowercased(), l.contains("waiting"), e.coresNow < 0.1 { return .waiting }
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
        case info                // advice with nothing to press
        case share               // show the anonymised case report, then offer to open it as a GitHub issue
        case openPage(String, String)   // open a page of an app's own settings in that app: bundle path, address
    }
    public let id: String
    public let title: String
    public let consequence: String
    public let kind: Kind
    public var recommended = false
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
        case .cooler: return 1
        case .info, .openPage: return f.id == "nostop" ? 7 : 2
        case .lookUp: return 3
        case .quitApp: return 4
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
            case .cooler, .stop, .quitApp, .lookUp, .openPage: return true
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
                            frontApp: String? = nil) -> Card {
        let who = subject(e)
        let since = busySince ?? e.start ?? now
        let busyFor = now.timeIntervalSince(since)
        let state = Health.assess(e, now: now, busySince: busySince)
        let atStake = now.timeIntervalSince(e.workStart ?? e.start ?? now)
        let output = e.writing.first { !Evidence.isLog($0) }.map { ($0 as NSString).lastPathComponent }

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
            let explanation = long
                ? "It usually takes under \(Fmt.duration(k.usualHours * 3600)). This has gone on for \(Fmt.duration(busyFor))."
                : "Normal \(k.normal)." + (k.endsOnItsOwn ? " It stops on its own." : "")
            var fixes: [Fix] = []
            if long {
                if k.whenLong == "Look it up" { fixes.append(lookUp(e.name, recommended: true)) }
                else {
                    fixes.append(Fix(id: "advice", title: k.whenLong, consequence: k.risk ?? "", kind: .info, recommended: true))
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
            if !e.mine { fixes.append(Fix(id: "nostop", title: "macOS needs this", consequence: "Stopping it would just restart it.", kind: .info)) }
            let head = e.coresNow < 0.25 ? "\(k.doing). It's quiet now."
                : long ? "\(k.doing), for \(Fmt.duration(busyFor)). That's longer than usual."
                : "\(k.doing). That's normal."
            return Card(state: e.coresNow < 0.25 ? .quiet : long ? .unknown : .working, headline: head, explanation: explanation, fixes: fixes)
        }

        // Chrome and other Chromium browsers, without quitting them (Phil, 15 November 2026: "Chrome is one of the
        // biggest causes, so we should look into if there are ways we can improve performance without killing it when a
        // user is using it"). A process can be told apart as a tab, an extension or the graphics process, but not which
        // tab: only the browser's Task Manager knows that.
        if let part = e.browserPart, let app = e.app, let bundle = e.appBundle {
            let inFront = frontApp == bundle                 // you're using the browser: the busy tab may be the one you're on
            let what = part == .tab ? "One tab" : part == .extensionPart ? "One extension" : "Its graphics process"
            let explanation = "\(what) has used about \(Fmt.cores(e.coresNow)) for \(Fmt.duration(busyFor))."
                + (part == .graphics ? " Usually video or animation." : " Only \(app) knows which.")
                + (warm && e.coresNow >= 0.5 ? " It's adding to the heat." : "")
            let canCool = e.mine && e.coresNow >= 0.5 && part != .graphics     // slowing graphics would slow all of it
            let page = { (url: String, title: String, why: String, rec: Bool) in
                Fix(id: "page", title: title, consequence: why, kind: .openPage(bundle, url), recommended: rec) }
            let find = Fix(id: "find", title: part == .extensionPart ? "Find the busy extension" : "Find the busy tab", consequence: "In \(app): Window ▸ Task Manager, sort by CPU.", kind: .info)
            let quit = Fix(id: "quit", title: "Quit \(app)", consequence: "Closes all tabs.", kind: .quitApp(bundle))
            var fixes: [Fix?]
            switch part {
            case .tab:
                fixes = [canCool ? Fix(id: "cooler", title: "Run this tab cooler", consequence: "Only this tab slows. Undo any time.", kind: .cooler, recommended: !inFront) : nil,
                         page("chrome://settings/performance", "Turn on Energy Saver", "Opens \(app)'s Performance settings. Less background work, lower frame rates.", inFront || !canCool),
                         find,
                         e.mine ? Fix(id: "closetab", title: "Close just that tab", consequence: "It shows a crash page; Reload brings it back. Anything typed in it is lost.", kind: .stop) : nil,
                         quit]
            case .extensionPart:
                fixes = [page("chrome://extensions", "Turn off the extension", "Opens \(app)'s extensions page. Switch off the one you don't need.", true),
                         canCool ? Fix(id: "cooler", title: "Run it cooler", consequence: "Only this extension slows. Undo any time.", kind: .cooler) : nil,
                         find,
                         e.mine ? Fix(id: "stopext", title: "Stop the extension", consequence: "\(app) says it crashed. Reload it from the extensions page.", kind: .stop) : nil,
                         quit]
            case .graphics:
                fixes = [page("chrome://settings/performance", "Turn on Energy Saver", "Opens \(app)'s Performance settings. Lower frame rates, less heat.", true),
                         find, quit]
            }
            let head = part == .tab ? "A \(app) tab is working hard." : part == .extensionPart ? "A \(app) extension is working hard."
                : "\(app) is drawing a lot: video or animation in a tab."
            return Card(state: e.coresNow < 0.25 ? .quiet : busyFor > 20 * 60 ? .unknown : .starting,
                        headline: head, explanation: explanation, fixes: fixes.compactMap { $0 })
        }

        // web pages: the busy process is a tab or extension, and only the browser knows which
        let webkit = e.name == "com.apple.WebKit.WebContent" || (e.path?.contains("com.apple.WebKit.WebContent") ?? false)
        if let app = webkit ? "Safari" : e.app, webkit || e.name.contains("Renderer") || e.name.contains("Web Content") || e.name.contains("(Plugin)") {
            let tm = app.contains("Safari") ? "Window ▸ Activity" : "Window ▸ Task Manager"
            return Card(state: e.coresNow < 0.25 ? .quiet : busyFor > 20 * 60 ? .unknown : .starting,
                        headline: "A \(app) tab is working hard.",
                        explanation: "One tab or extension has used about \(Fmt.cores(e.coresNow)) for \(Fmt.duration(busyFor)). Only \(app) knows which.",
                        fixes: [Fix(id: "find", title: "Find the busy tab", consequence: "In \(app): \(tm), sort by CPU.", kind: .info, recommended: true),
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
            if e.coresNow < 0.25 { return Card(state: .quiet, headline: "\(name) is quiet now.", explanation: "", fixes: []) }
            return Card(state: .working, headline: "\(name) is a game. Games keep your Mac busy while they run.",
                        explanation: "That's normal while you play." + (warm ? " It's adding to the heat." : ""),
                        fixes: [Fix(id: "settings", title: "Lower its graphics settings", consequence: "In the game's settings: lower quality or frame rate. Less heat, still smooth.", kind: .info, recommended: warm),
                                Fix(id: "quit", title: "Quit \(name)", consequence: "Save your game first. Unsaved progress may be lost.", kind: .quitApp(game))])
        }

        // while a game is being played, other busy work is the thing to slow, so the game runs smoothly
        let forGame = gameRunning != nil && cooler != nil
        let cool = cooler.map { c -> Fix in
            var c = c; c.recommended = warm || forGame
            if let g = gameRunning { c = Fix(id: c.id, title: c.title, consequence: "Leaves more power for \(g). Undo any time.", kind: c.kind, recommended: c.recommended) }
            return c
        }
        // while the Mac is warm, a busy job says it is part of why
        let heat = (warm && e.coresNow >= 0.5 ? " It's adding to the heat." : "") + (forGame ? " It's competing with \(gameRunning!)." : "")
        switch state {
        case .working:
            if let p = e.progress {
                var head = "\(who) is " + (p.fraction.map { "\(Fmt.percent($0)) done." } ?? "making progress.")
                if let fin = p.finish { head += fin > now ? " Ready around \(Fmt.time(fin))." : " Almost done." }
                return Card(state: state, headline: head, explanation: "Its log says \u{201C}\(p.line)\u{201D}." + heat,
                            fixes: [wait(until: p.finish, now: now, recommended: !warm || cooler == nil), cool, stop].compactMap { $0 })
            }
            return Card(state: state, headline: "\(who) is busy and still saving its work.",
                        explanation: "It doesn't say how far along it is." + heat,
                        fixes: [wait(until: nil, now: now, recommended: !warm || cooler == nil), cool, stop].compactMap { $0 })
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
                        fixes: [lookUp(e.name, recommended: !forGame), wait(until: nil, now: now, recommended: false),
                                forGame ? cool : cooler,
                                stop.map { var f = $0; f = Fix(id: f.id, title: f.title, consequence: "Only if you know what it is. " + f.consequence, kind: f.kind); return f },
                                share].compactMap { $0 })
        case .starting:
            return Card(state: state, headline: "\(who) just started. Give it a minute.", explanation: "Started at \(Fmt.time(e.start ?? now)).",
                        fixes: [wait(until: nil, now: now, recommended: true), forGame ? cool : cooler, stop].compactMap { $0 })
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
