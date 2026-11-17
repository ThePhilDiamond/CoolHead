import Foundation

/// Any busy job no other card explains: a script, a command-line tool or an app, by how it's doing (see Health in
/// Card.swift): making progress, waiting, stuck, or not saying.
enum JobCard: ProcessCard {
    static let name = "a busy program"
    static let id = "job"
    static let kind = CardKind.catchAll
    static let rule = "Stopping is recommended only when a job has stalled (Phil); on battery, only the really hungry or long-running are paused (Phil, 15 November 2026)"
    /// It fits any busy program, so it knows least; its reason is what it does know, from the job's own signs.
    static func confidence(_ s: Situation) -> Confidence {
        switch s.state {
        case .stalled: return .any("it has stopped making progress")
        case .working where s.e.progress != nil: return .any("its log says how far along it is")
        case .waiting: return .any("it's waiting for another job")
        default: return .any("we can't tell what it's doing from outside it")
        }
    }
    static let samples = ["job-with-progress", "job-stalled", "job-waiting", "job-no-signs", "job-just-started", "virtual-machine", "background-helper", "intel-app-26"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        c.diagnosis = diagnosis(s)
        c.optionFacts = facts(s)
        return c
    }

    /// What it saw, from the job's own signs: "it has been busy for 3 hours without saying what it's doing and is
    /// adding to the heat".
    static func diagnosis(_ s: Situation) -> Diagnosis {
        let e = s.e
        var signs: [String]
        var means: String? = nil
        switch s.state {
        case .working:
            signs = [e.progress?.fraction.map { "is \(Fmt.percent($0)) done" } ?? (e.progress != nil ? "is making progress" : "is busy and still saving its work")]
        case .waiting: signs = ["is waiting for another job and isn't using your Mac's power"]
        case .stalled:
            signs = ["hasn't made any progress for \(Fmt.duration(s.now.timeIntervalSince(e.progress?.lineTime ?? s.now)))"]
            means = "it's stuck, using power without getting anywhere"
        case .unknown: signs = ["'s been busy for \(Fmt.duration(s.busyFor)) without saying what it's doing"]
        case .starting: signs = ["only just started"]
        case .quiet: signs = ["is quiet now"]
        }
        if s.state != .stalled && s.state != .waiting && s.state != .quiet {
            if s.onBattery && e.coresNow >= 1 { signs.append("is draining your battery") }
            if s.warm && s.heating { signs.append("is adding to the heat") }
            if let g = s.gameRunning, s.cooler != nil || s.gpuLed { signs.append("is competing with \(g)") }
            if s.gpuLed { signs.append("is keeping the graphics chip busy") }
        }
        // "it's 96% done and is adding to the heat"
        if signs[0].hasPrefix("is ") { signs[0] = "'s " + signs[0].dropFirst(3) } else if !signs[0].hasPrefix("'") { signs[0] = " " + signs[0] }
        return Diagnosis(saw: "it" + Decision.list(signs), means: means)
    }

    /// Its options' facts, in its own words where the kind's words don't fit.
    static func facts(_ s: Situation) -> [String: OptionFacts] {
        var out: [String: OptionFacts] = [:]
        if s.state == .stalled, let p = s.e.progress {
            out["stop"] = OptionFacts(helps: "frees the power it's been using", cost: "it can't be undone", stakes: .nothingLostSince(Fmt.time(p.lineTime)))
        } else {
            out["stop"] = OptionFacts(helps: "ends the load completely", cost: "nothing gets a chance to save",
                                      when: s.state == .unknown ? "if you know what it is and don't need it" : nil,
                                      stakes: s.atStake >= 10 * 60 ? .mayLose(Fmt.duration(s.atStake)) : nil)
        }
        if let g = s.gameRunning { out["cooler"] = OptionFacts(helps: "leaves more power for \(g)", undo: .anyTime) }
        if let app = s.e.quittableApp, s.gpuLed {
            out["quit"] = OptionFacts(helps: "closes \(app), which lets the graphics chip rest", stakes: .protected("\(app) asks about anything unsaved first"))
        }
        return out
    }

    static func made(_ s: Situation) -> Card? {
        let e = s.e, now = s.now, who = s.who, warm = s.warm, cooler = s.cooler, stop = s.stop
        // while a game is being played, other busy work is the thing to slow, so the game runs smoothly
        let forGame = s.gameRunning != nil && cooler != nil
        // on battery, with Save Battery When Unplugged on: a heavy job (a script or command-line tool, never an app)
        // can be frozen until the Mac is plugged in. Nothing is lost, unlike stopping it (Phil's rule: stopping is
        // recommended only when a job has stalled).
        let pausable = e.mine && (e.script != nil || (e.appBundle == nil && !(e.path.map(CaseReport.isMacOS) ?? true)))
        // only the really hungry or long-running while the battery is healthy; any steady load once it's under half
        // (Phil, 15 November 2026: "only be aggressive to really hungry /extended processes or when battery is below 50%")
        let hungry = (e.coresNow >= 2 && s.busyFor >= 600) || (e.coresNow >= 1 && s.busyFor >= 1800)
        let drains = s.onBattery && pausable && s.state != .stalled && e.coresNow >= 1 && s.busyFor >= 600
            && (hungry || (s.battery ?? 100) < 50)
        let pauseFix: Fix? = drains ? Fix(id: "pausejob", title: "Pause until you plug in",
                                          consequence: "Frozen, nothing lost; it carries on when you plug in. A download may time out.",
                                          kind: .pauseJob, recommended: true) : nil
        let cool = cooler.map { c -> Fix in
            var c = c; c.recommended = (warm || forGame) && !RunCooler.isVirtualMachine(e)   // slowing a VM slows all of it: offered, not advised
            if let g = s.gameRunning { c = Fix(id: c.id, title: c.title, consequence: "Leaves more power for \(g). Undo any time.", kind: c.kind, recommended: c.recommended) }
            return c
        }
        // an app here for the graphics chip: what lets the chip rest, and quitting it (slowing it wouldn't help: background
        // priority slows its CPU work, not its drawing)
        let gpuApp = s.gpuLed ? e.quittableApp : nil
        let gpuQuit = gpuApp.flatMap { app in e.quittableBundle.map {
            Fix(id: "quit", title: "Quit \(app)", consequence: "Lets the graphics chip rest. It asks about anything unsaved.", kind: .quitApp($0)) } }
        // while the Mac is warm, a busy job says it is part of why
        let heat = Fmt.its([s.gpuClause, warm && s.heating ? "adding to the heat" : nil,
                            forGame || (s.gameRunning != nil && s.gpuLed) ? "competing with \(s.gameRunning!)" : nil, drains ? "draining your battery" : nil])
            + (gpuApp != nil ? " Pausing or closing a video, animation or 3D view in it lets the chip rest." : "")
        switch s.state {
        case .working:
            if let p = e.progress {
                var head = "\(who) is " + (p.fraction.map { "\(Fmt.percent($0)) done." } ?? "making progress.")
                if let fin = p.finish { head += fin > now ? " Ready around \(Fmt.time(fin))." : " Almost done." }
                return Card(state: s.state, headline: head, explanation: "Its log says \u{201C}\(p.line)\u{201D}." + heat,
                            fixes: [pauseFix, Card.wait(until: p.finish, now: now, recommended: !warm || cooler == nil), cool, gpuQuit, stop].compactMap { $0 })
            }
            return Card(state: s.state, headline: "\(who) is busy and still saving its work.",
                        explanation: "It doesn't say how far along it is." + heat,
                        fixes: [pauseFix, Card.wait(until: nil, now: now, recommended: !warm || cooler == nil), cool, gpuQuit, stop].compactMap { $0 })
        case .waiting:
            return Card(state: s.state, headline: "\(who) is waiting for another job.",
                        explanation: "It isn't using your Mac's power while it waits.",
                        fixes: [Card.wait(until: nil, now: now, recommended: true), stop].compactMap { $0 })
        case .stalled:
            let at = e.progress.map { Fmt.time($0.lineTime) } ?? "a while"
            return Card(state: s.state, headline: "\(who) hasn't moved since \(at). It looks stuck.",
                        explanation: "No new progress for \(Fmt.duration(now.timeIntervalSince(e.progress?.lineTime ?? now))).",
                        fixes: [stop ?? Card.lookUp(e.name, recommended: true), Card.wait(until: nil, now: now, recommended: false), Card.share])
        case .unknown:
            return Card(state: s.state, headline: "\(who) has been busy for \(Fmt.duration(s.busyFor)). We can't tell why.",
                        explanation: "It isn't saying what it's doing." + heat,
                        fixes: [pauseFix, Card.lookUp(e.name, recommended: !forGame), Card.wait(until: nil, now: now, recommended: false),
                                forGame ? cool : cooler, gpuQuit,
                                stop.map { var f = $0; f = Fix(id: f.id, title: f.title, consequence: "Only if you know what it is. " + f.consequence, kind: f.kind); return f },
                                Card.share].compactMap { $0 })
        case .starting:
            return Card(state: s.state, headline: "\(who) just started. Give it a minute.", explanation: "Started at \(Fmt.time(e.start ?? now))." + heat,
                        fixes: [pauseFix, Card.wait(until: nil, now: now, recommended: true), forGame ? cool : cooler, gpuQuit, stop].compactMap { $0 })
        case .quiet:
            return Card(state: s.state, headline: "\(who) is quiet now.", explanation: "", fixes: [])
        }
    }
}
