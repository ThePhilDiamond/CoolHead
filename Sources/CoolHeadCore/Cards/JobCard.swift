import Foundation

/// Any busy job no other card explains: a script, a command-line tool or an app, by how it's doing (see Health in
/// Card.swift): making progress, waiting, stuck, or not saying.
enum JobCard: ProcessCard {
    static let name = "a busy program"
    static let id = "job"
    static let kind = CardKind.catchAll
    static let rule = "Stopping is recommended only when a job has stalled; on battery, only the really hungry or long-running are paused"
    /// It fits any busy program, so it knows least; its reason is what it does know, from the job's own signs.
    static func confidence(_ s: Situation) -> Confidence {
        switch s.state {
        case .stalled: return .any("it has stopped making progress")
        case .working where s.e.progress != nil: return .any("its log says how far along it is")
        case .waiting: return .any("it's waiting for another job")
        default: return .any("we can't tell what it's doing from outside it")
        }
    }
    /// Before Stop it's cost when nobody can tell what the job is (its state is unknown); the memory card says it too.
    static let onlyIfKnown = "Use this only if you know what it is. "
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
        // can be frozen until the Mac is plugged in. Nothing is lost, unlike stopping it, which is recommended only
        // when a job has stalled.
        let pausable = e.mine && (e.script != nil || (e.appBundle == nil && !(e.path.map(CaseReport.isMacOS) ?? true)))
        // only the really hungry or long-running while the battery is healthy; any steady load once it's under half
        let hungry = (e.coresNow >= 2 && s.busyFor >= 600) || (e.coresNow >= 1 && s.busyFor >= 1800)
        let drains = s.onBattery && pausable && s.state != .stalled && e.coresNow >= 1 && s.busyFor >= 600
            && (hungry || (s.battery ?? 100) < 50)
        // not while it's playing sound or downloading (see BusyWith): the card says why instead
        let pauseFix: Fix? = drains && s.busyWith == nil
            ? Fix(id: "pausejob", title: "Pause until you connect the charger",
                  consequence: CardTemplate.says(nil, .nothing) + " A download may stop.",
                  kind: .pauseJob, recommended: true) : nil
        let cool = cooler.map { c -> Fix in
            var c = c; c.recommended = (warm || forGame) && !RunCooler.isVirtualMachine(e)   // slowing a VM slows all of it: offered, not advised
            if let g = s.gameRunning { c = Fix(id: c.id, title: c.title, consequence: CardTemplate.says("This lets \(g) run faster.", undo: true), kind: c.kind, recommended: c.recommended) }
            return c
        }
        // an app here for the graphics chip: what lets the chip rest, and quitting it (slowing it wouldn't help: background
        // priority slows its CPU work, not its drawing)
        let gpuApp = s.gpuLed ? e.quittableApp : nil
        let gpuQuit = gpuApp.flatMap { app in e.quittableBundle.map {
            Fix(id: "quit", title: "Quit \(app)", consequence: CardTemplate.says("This lets the graphics chip rest.", .asksToSave), kind: .quitApp($0)) } }
        // what it means for you, in one sentence of plain verbs (see CardTemplate.it)
        let game = forGame || (s.gameRunning != nil && s.gpuLed) ? s.gameRunning : nil
        let effect = [CardTemplate.it([warm && s.heating ? "adds heat" : nil, game.map { "slows \($0)" },
                                       drains ? "uses a lot of battery power" : nil])].compactMap { $0 }
            + (gpuApp != nil ? ["If you pause or close a video, animation, or 3D view in it, the graphics chip can rest."] : [])
            + (drains ? s.busyWith.map { [$0.cardLine] } ?? [] : [])
        // how we know, with the graphics chip's share (the job card's reading is never the graphics chip)
        func evidence(_ first: String?) -> [String] { [first, s.graphics].compactMap { $0 } }
        switch s.state {
        case .working:
            if let p = e.progress {
                // the headline gives how far, from the log; the line itself is in Nerdy stuff (Watcher's "Progress:"),
                // so its figures aren't said again here, and a long machine-written line never fills the card
                let verdict: CardTemplate.Verdict = p.finish.map { $0 > now ? .finishAt($0) : .almostDone } ?? .normal
                let reading: CardTemplate.Reading = p.fraction.map { .done($0) } ?? .working
                return Card(state: s.state, CardTemplate(who, reading, verdict, evidence: evidence("Its own log reports this."), effect: effect),
                            fixes: [pauseFix, Card.wait(until: p.finish, now: now, recommended: !warm || cooler == nil), cool, gpuQuit, stop].compactMap { $0 })
            }
            return Card(state: s.state, CardTemplate(who, .working, .normal, evidence: evidence("It still writes its results. It does not report how far it is."), effect: effect),
                        fixes: [pauseFix, Card.wait(until: nil, now: now, recommended: !warm || cooler == nil), cool, gpuQuit, stop].compactMap { $0 })
        case .waiting:
            return Card(state: s.state, CardTemplate(who, .waitsFor("another job"), .normal, evidence: ["It does almost no work while it waits."]),
                        fixes: [Card.wait(until: nil, now: now, recommended: true), stop].compactMap { $0 })
        case .stalled:
            let reading: CardTemplate.Reading = e.progress.map { .noProgressAfter($0.lineTime) } ?? .busyFor(s.busyFor)
            // the headline says it all; no explanation restates it (each fact once, docs/BRAND.md)
            return Card(state: s.state, CardTemplate(who, reading, .probablyStuck),
                        // the headline gives the time of its last progress, so Stop doesn't say it again (each fact once)
                        fixes: [stop.map { Fix(id: $0.id, title: $0.title, consequence: "You lose no work from after its last progress.", kind: $0.kind, recommended: $0.recommended) }
                                    ?? Card.lookUp(e.name, recommended: true), Card.wait(until: nil, now: now, recommended: false), Card.share])
        case .unknown:
            // nothing says what it's doing, and the card doesn't say so either: a card says what Cool Head knows, so
            // where it says nothing, Cool Head doesn't know; the verdict says it costs more than usual
            return Card(state: s.state, CardTemplate(who, .busyFor(s.busyFor), .moreThanUsual, evidence: evidence(nil), effect: effect),
                        fixes: [pauseFix, Card.lookUp(e.name, recommended: !forGame), Card.wait(until: nil, now: now, recommended: false),
                                forGame ? cool : cooler, gpuQuit,
                                // when what's at stake is the headline's busy time as shown, it isn't said again
                                stop.map { f in
                                    let lose = Fmt.duration(s.atStake) == Fmt.duration(s.busyFor) ? CardTemplate.Loss.workItDid.sentence : f.consequence
                                    return Fix(id: f.id, title: f.title, consequence: JobCard.onlyIfKnown + lose, kind: f.kind) },
                                Card.share].compactMap { $0 })
        case .starting:
            return Card(state: s.state, CardTemplate(who, .startedAt(e.start ?? now), .waitAFewMinutes, evidence: evidence(nil), effect: effect),
                        fixes: [pauseFix, Card.wait(until: nil, now: now, recommended: true), forGame ? cool : cooler, gpuQuit, stop].compactMap { $0 })
        case .quiet:
            return Card(state: s.state, CardTemplate(who, .quiet, nil), fixes: [])
        }
    }
}
