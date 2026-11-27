import Foundation

/// One of macOS's own processes that the catalogue knows (Catalogue.swift): what it is doing, and whether this has
/// gone on longer than usual.
enum CatalogueCard: ProcessCard {
    static let name = "a program we know by name"
    static let id = "catalogue"
    static let kind = CardKind.explanation
    static let rule = "Catalogue.swift: macOS's own processes, what each does and how long it usually takes"
    static func confidence(_ s: Situation) -> Confidence { .named("we know this program and what usually helps it") }
    static let samples = ["spotlight-normal", "spotlight-long", "kernel-task-long", "docker-vm", "windowserver-old-electron", "time-machine-build"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        let e = s.e
        guard let k = Pattern.match(name: e.name, path: e.path, pid: e.pid) else { return c }
        let updated = k.afterUpdate ? s.background?.update : nil
        let long = updated == nil && s.busyFor > k.usualHours * 3600 && s.busyFor >= 20 * 60
        if let feed = k.id == "time-machine" && s.active ? s.backupFeed : nil {
            c.diagnosis = Diagnosis(saw: "Time Machine keeps copying \(feed.name), the build folder \(feed.who) writes, which changes every time it builds")
            c.optionFacts["backup"] = OptionFacts(helps: "stops Time Machine copying \(feed.name) again and again", undo: .anyTime,
                                                  stakes: .protected("it's build output, which a build makes again"))
        } else if long {
            c.diagnosis = Diagnosis(saw: "it's been busy for \(Fmt.duration(s.busyFor)), longer than the \(Fmt.duration(k.usualHours * 3600)) it usually takes")
        } else {
            c.diagnosis = Diagnosis(saw: k.doing + (updated != nil ? ", which is normal after an update" : ", which is normal"))
        }
        // what the catalogue's advice does, for each entry that has its own
        let advice: [String: OptionFacts] = [
            "kernel-task": OptionFacts(helps: "shows which app is making the heat that macOS is holding the chip back for"),
            "docker-vm": OptionFacts(helps: "ends the virtual machine's load when nothing needs it"),
            "sound": OptionFacts(helps: "removes the likely cause: a virtual microphone, or an app that hides the microphone dot"),
            "contacts-sync": OptionFacts(helps: "removes the likely cause on macOS 26.4 and later"),
            "messages-sync": OptionFacts(helps: "pauses the syncing that keeps it busy", cost: "older messages may not show on this Mac until you turn it on again"),
            "aerial-downloads": OptionFacts(helps: "likely stops the new downloads"),
            "displaylink": OptionFacts(helps: "starts it fresh", cost: "your DisplayLink screens go dark until it's running again"),
            "local-ai-model": OptionFacts(helps: "frees the power and memory it's using",
                                          cost: "anything using the model gets no answers until it loads again, which takes a few seconds"),
        ]
        if let f = advice[k.id] { c.optionFacts["advice"] = f }
        c.optionFacts["lookup"] = OptionFacts(helps: "may say why it's taking longer than usual")
        let quitCost = ["docker-vm": "every container stops", "displaylink": "your DisplayLink screens go dark until it's running again"]
        if let cost = quitCost[k.id], let app = e.quittableApp {
            c.optionFacts["quit"] = OptionFacts(helps: "ends \(app)'s load completely", cost: cost)
        }
        return c
    }

    static func made(_ s: Situation) -> Card? {
        let e = s.e
        guard let k = Pattern.match(name: e.name, path: e.path, pid: e.pid), e.progress == nil else { return nil }
        // after a macOS update, indexing and analysis are expected for hours to days (see BackgroundWork)
        let updated = k.afterUpdate ? s.background?.update : nil
        let long = updated == nil && s.busyFor > k.usualHours * 3600 && s.busyFor >= 20 * 60
        // its busy threads at background priority: on the efficiency cores, little heat whatever % CPU says
        let cool = s.active && s.background?.cool == true ? "It runs at low priority, so it makes little heat." : nil
        // Time Machine copying a build's output: the build folder is the cause to fix (see BackupExclusions)
        let feed = k.id == "time-machine" && s.active ? s.backupFeed : nil
        let evidence: [String] = long
            ? ["It started \(Fmt.duration(s.busyFor)) ago, and it usually takes less than \(Fmt.duration(k.usualHours * 3600))."]
            : updated.map { ["You updated to macOS \($0.version) \(BackgroundWork.ago($0.date, now: s.now)).", "Work like this usually continues for hours or days after an update."] }
                ?? [k.usually + (k.endsOnItsOwn ? " It stops on its own." : "")]
        var fixes: [Fix] = feed.map { [$0.fix(recommended: true)] } ?? []
        if long {
            if k.whenLong == "Search the web" { fixes.append(Card.lookUp(e.name, recommended: true)) }
            else {
                // what the catalogue advises, as a button: open the app it's about, or Activity Monitor to find the heat
                // (an option to quit says its cost on the Quit option, so opening the app doesn't say it too)
                let quits = k.whenLong.hasPrefix("Quit") || k.whenLong.hasPrefix("Restart")
                if k.whenLong.hasPrefix("Restart"), let bundle = e.quittableBundle {
                    // a restart Cool Head can do itself, in one click: a normal quit, then it opens again by itself (what
                    // was off while it was closed, such as DisplayLink's screens, comes back with it)
                    fixes.append(Fix(id: "advice", title: k.whenLong, consequence: "This quits it and opens it again." + (k.risk.map { " " + $0 } ?? ""),
                                     kind: .restartApp(bundle), recommended: true))
                } else if k.whenLong.hasPrefix("Find what is heating") {
                    fixes.append(Fix.openApp("advice", k.whenLong, bundle: Fix.activityMonitor, steps: "Click % CPU to put the busiest first.", recommended: true))
                } else if let b = e.appBundle {
                    fixes.append(Fix.openApp("advice", k.whenLong, bundle: b, steps: k.whenLong.hasPrefix("Restart") ? "Quit it, then open it again." + (k.risk.map { " " + $0 } ?? "") : quits ? "" : (k.risk ?? ""), recommended: true))
                } else {
                    fixes.append(Fix.guide("advice", k.whenLong, "This shows the steps." + (k.risk.map { " " + $0 } ?? ""),
                                           steps: [k.whenLong + ".", k.risk].compactMap { $0 }, recommended: true))
                }
                fixes.append(Card.lookUp(e.name, recommended: false))
            }
            fixes.append(Card.wait(until: nil, now: s.now, recommended: false))
            fixes.append(Card.share)
        } else {
            fixes.append(Card.wait(until: nil, now: s.now, recommended: true))
        }
        if let bundle = e.quittableBundle, let app = e.quittableApp, k.risk != nil, k.whenLong.hasPrefix("Quit") || k.whenLong.hasPrefix("Restart") {
            let quit = Fix(id: "quit", title: "Quit \(app)", consequence: k.risk!.hasPrefix("This ") ? k.risk! : "This quits it. " + k.risk!, kind: .quitApp(bundle))
            fixes.append(k.quitLosesWork ? quit.losingWork() : quit)
        }
        let verdict: CardTemplate.Verdict = !s.active ? .notBusyNow : long ? .longerThanUsual : updated != nil ? .normalAfterUpdate : .normal
        // a statement, not an option: macOS restarts its own programs
        return Card(state: !s.active ? .quiet : long ? .unknown : .working,
                    CardTemplate(k.doing, nil, verdict,
                                 // no "if you stop it, macOS starts it again": these cards offer no Stop, so it answers a question they never
                                 // raise; the graphics chip's share is in Nerdy stuff
                                 evidence: evidence + [cool].compactMap { $0 } + (feed.map { [$0.sentence()] } ?? [])),
                    fixes: fixes)
    }
}
