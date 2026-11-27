import Foundation

/// Chrome and other Chromium-style apps, without quitting them: Chrome is one of the biggest causes of a slow Mac, and
/// someone using it shouldn't have to quit it to make it faster. A process can be told apart as a tab, an extension, or
/// the graphics process, but not which tab: only the browser's Task Manager knows that.
enum ChromiumBrowserCard: ProcessCard {
    static let name = "a browser tab or extension"
    static let id = "chromium-browser"
    static let kind = CardKind.explanation
    static let rule = "Improve Chrome's performance without quitting it"
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
        // one shape for every card about how hard something works (docs/BRAND.md, Voice): who and how hard in the
        // headline, what it's doing or who knows which in the explanation
        let evidence = [part == .graphics ? "It draws video or animation in a tab." : part == .tab ? "Only \(app) knows which tab." : "Only \(app) knows which extension.",
                        s.gpuLed ? nil : s.graphics].compactMap { $0 }
        let effect = [CardTemplate.it([s.warm && s.heating ? "adds heat" : nil])].compactMap { $0 }
        let canCool = RunCooler.offered(e) && part != .graphics     // slowing graphics would slow all of it
        let page = { (url: String, title: String, why: String, rec: Bool) in
            Fix(id: "page", title: title, consequence: why, kind: .openPage(bundle, url), recommended: rec) }
        let find = Fix.openApp("find", part == .extensionPart ? "Find the busy extension" : "Find the busy tab", bundle: bundle, steps: [TaskManager.open(app), TaskManager.sort(by: "CPU", so: "the busiest"),
                                       part == .extensionPart ? "Its name shows which extension it is." : "Close that tab, or reload it if you need it."].joined(separator: " ")).fixingTheCause()
        let quit = Fix(id: "quit", title: "Quit \(app)", consequence: "This closes all its tabs.", kind: .quitApp(bundle)).losingWork()
        var fixes: [Fix?]
        switch part {
        case .tab:
            fixes = [canCool ? Fix(id: "cooler", title: "Run this tab cooler", consequence: CardTemplate.says("This slows only that tab.", undo: true), kind: .cooler, recommended: !inFront, holdBack: inFront) : nil,
                     page("chrome://settings/performance", "Turn on Energy Saver", "This opens \(app)'s Performance settings. Energy Saver lowers background work and frame rates.", inFront || !canCool),
                     find,
                     e.mine ? Fix(id: "closetab", title: "Close just that tab", consequence: CardTemplate.says("This leaves a crash page in the tab. Reload opens it again.", .unsaved), kind: .stop) : nil,
                     quit]
        case .extensionPart:
            fixes = [page("chrome://extensions", "Turn off the extension", "This opens \(app)'s extensions page. Turn off the one you do not need.", true).fixingTheCause(),
                     canCool ? Fix(id: "cooler", title: "Run it cooler", consequence: CardTemplate.says("This slows only that extension.", undo: true), kind: .cooler) : nil,
                     find,
                     e.mine ? Fix(id: "stopext", title: "Stop the extension", consequence: "This makes it show as crashed until you reload it.", kind: .stop) : nil,
                     quit]
        case .graphics:
            fixes = [page("chrome://settings/performance", "Turn on Energy Saver", "This opens \(app)'s Performance settings. Energy Saver lowers frame rates, so the Mac makes less heat.", true),
                     find, quit]
        }
        let subject = part == .tab ? "a \(app) tab" : part == .extensionPart ? "a \(app) extension" : app
        return Card(state: !s.active ? .quiet : s.busyFor > 20 * 60 ? .unknown : .starting,
                    CardTemplate(subject, s.reading, .moreThanUsual, evidence: evidence, effect: effect), fixes: fixes.compactMap { $0 })
    }
}
