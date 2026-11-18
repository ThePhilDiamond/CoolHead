import Foundation

/// Chrome and other Chromium-style apps, without quitting them (Phil, 15 November 2026: "Chrome is one of the biggest
/// causes, so we should look into if there are ways we can improve performance without killing it when a user is
/// using it"). A process can be told apart as a tab, an extension or the graphics process, but not which tab: only the
/// browser's Task Manager knows that.
enum ChromiumBrowserCard: ProcessCard {
    static let name = "a browser tab or extension"
    static let id = "chromium-browser"
    static let kind = CardKind.explanation
    static let rule = "Phil, 15 November 2026: improve Chrome's performance without quitting it"
    static func confidence(_ s: Situation) -> Confidence { .type("the app says this process is one of its tabs, extensions, or its graphics process") }
    static let samples = ["chrome-tab", "chrome-tab-in-front-warm", "chrome-extension", "chrome-graphics"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        if let part = s.e.browserPart, let app = s.e.app {
            let what = part == .tab ? "one \(app) tab" : part == .extensionPart ? "one \(app) extension" : "\(app)'s graphics process"
            var signs = [s.gpuLed ? "has kept \(Fmt.share(s.gpu)) of the graphics chip busy for \(Fmt.duration(s.busyFor))"
                                  : "has used about \(Fmt.cores(s.e.coresNow)) for \(Fmt.duration(s.busyFor))"]
            if s.warm && s.heating { signs.append("is adding to the heat") }
            c.diagnosis = Diagnosis(saw: what + " " + Decision.list(signs), subject: part == .extensionPart ? "the busy extension" : nil)
            let inFront = s.frontApp == s.e.appBundle
            c.optionFacts["cooler"] = OptionFacts(helps: part == .tab ? "slows only the busy tab" : "slows only the busy extension", undo: .anyTime)
            c.optionFacts["page"] = OptionFacts(helps: part == .extensionPart ? "keeps it from running again"
                                                : part == .graphics ? "lowers frame rates, so the graphics chip does less"
                                                : "cuts \(app)'s background work and frame rates")
            c.optionFacts["find"] = OptionFacts(helps: "shows which \(part == .extensionPart ? "extension" : "tab") is busy, so you can close it",
                                                whyNot: inFront ? "you may be using the busy tab, and Energy Saver eases it without closing anything" : nil)
            c.optionFacts["closetab"] = OptionFacts(helps: "ends the busy tab", cost: "anything typed in it is lost", undo: .other("Reload brings the page back."))
            c.optionFacts["stopext"] = OptionFacts(helps: "ends the busy extension", cost: "\(app) says it crashed until you reload it")
            c.optionFacts["quit"] = OptionFacts(helps: "ends the load completely", cost: "every tab closes")
        }
        return c
    }

    static func made(_ s: Situation) -> Card? {
        let e = s.e
        guard let part = e.browserPart, let app = e.app, let bundle = e.appBundle else { return nil }
        let inFront = s.frontApp == bundle                 // you're using the browser: the busy tab may be the one you're on
        let what = part == .tab ? "One tab" : part == .extensionPart ? "One extension" : "Its graphics process"
        let explanation = (s.gpuLed ? "\(what) has kept \(Fmt.share(s.gpu)) of the graphics chip busy for \(Fmt.duration(s.busyFor))."
                           : "\(what) has used about \(Fmt.cores(e.coresNow)) for \(Fmt.duration(s.busyFor)).")
            + (part == .graphics ? "" : " Only \(app) knows which.")
            + Fmt.its([s.gpuLed ? nil : s.gpuClause, s.warm && s.heating ? "adding to the heat" : nil])
        let canCool = RunCooler.offered(e) && part != .graphics     // slowing graphics would slow all of it
        let page = { (url: String, title: String, why: String, rec: Bool) in
            Fix(id: "page", title: title, consequence: why, kind: .openPage(bundle, url), recommended: rec) }
        let find = Fix.openApp("find", part == .extensionPart ? "Find the busy extension" : "Find the busy tab", bundle: bundle, steps: [TaskManager.open(app), TaskManager.sort(by: "CPU", so: "the busiest"),
                                       part == .extensionPart ? "Its name says which extension it is." : "Close that tab, or reload it if you need it."].joined(separator: " ")).fixingTheCause()
        let quit = Fix(id: "quit", title: "Quit \(app)", consequence: "Closes all tabs.", kind: .quitApp(bundle)).losingWork()
        var fixes: [Fix?]
        switch part {
        case .tab:
            fixes = [canCool ? Fix(id: "cooler", title: "Run this tab cooler", consequence: "Only this tab slows. Undo any time.", kind: .cooler, recommended: !inFront, holdBack: inFront) : nil,
                     page("chrome://settings/performance", "Turn on Energy Saver", "Takes you to \(app)'s Performance settings. Less background work, lower frame rates.", inFront || !canCool),
                     find,
                     e.mine ? Fix(id: "closetab", title: "Close just that tab", consequence: "It shows a crash page; Reload brings it back. Anything typed in it is lost.", kind: .stop) : nil,
                     quit]
        case .extensionPart:
            fixes = [page("chrome://extensions", "Turn off the extension", "Takes you to \(app)'s extensions page. Switch off the one you don't need.", true).fixingTheCause(),
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
        return Card(state: !s.active ? .quiet : s.busyFor > 20 * 60 ? .unknown : .starting,
                    headline: head, explanation: explanation, fixes: fixes.compactMap { $0 })
    }
}
