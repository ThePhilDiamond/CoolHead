import Foundation

/// Web pages: the busy process is a tab or extension, and only the browser knows which. WebKit's graphics process
/// draws web pages for Safari, and for any other app that shows them: when macOS doesn't say which app it's for, it's
/// most often Safari.
enum WebPageCard: ProcessCard {
    static let name = "a web page"
    static let id = "web-page"
    static let kind = CardKind.explanation
    static let rule = "A browser's busy tab: only the browser's own task manager knows which"
    /// Sure for macOS's own web page process showing Safari's pages (or not saying for which app); otherwise it goes
    /// by the process's name, which other apps' helpers can share.
    static func confidence(_ s: Situation) -> Confidence {
        s.webkit && (s.e.servedBy.map(Served.isSafari) ?? true) ? .named("it's macOS's own web page process, working for Safari") : .guess("the process's name says it shows web pages")
    }
    static let samples = ["browser-tab", "safari-tab", "web-page-drawing"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        let app = s.webkit ? "Safari" : (s.e.app ?? "the browser")
        c.diagnosis = Diagnosis(saw: s.webkitGPU ? "a web page is drawing a lot, usually video or animation" : "one \(app) tab or extension \(s.used.dropLast())")
        c.optionFacts["find"] = OptionFacts(helps: "shows which tab is busy, so you can close it")
        c.optionFacts["quit"] = OptionFacts(helps: "ends the load completely", cost: "every tab closes")
        return c
    }

    static func made(_ s: Situation) -> Card? {
        let e = s.e
        guard let app = s.webkit ? "Safari" : e.app,
              s.webkit || e.name.contains("Renderer") || e.name.contains("Web Content") || e.name.contains("(Plugin)") else { return nil }
        let steps = [TaskManager.open(app.contains("Safari") ? "Safari" : app), TaskManager.sort(by: "CPU", so: "the busiest tab"), "Close that tab, or reload it if you need it."]
        let forSafari = e.servedBy.map(Served.isSafari) == true
        let bundle = e.outerBundle ?? (s.webkit ? "/Applications/Safari.app" : nil)
        return Card(state: !s.active ? .quiet : s.busyFor > 20 * 60 ? .unknown : .starting,
                    headline: s.webkitGPU ? "A web page is drawing a lot: video or animation." : "A \(app) tab is working hard.",
                    explanation: (s.webkitGPU ? (forSafari ? "The process that draws Safari's pages \(s.used)"
                                               : "The process that draws web pages \(s.used) It's usually a Safari tab, though other apps that show web pages have one too.")
                        : "One tab or extension \(s.used) Only \(app) knows which.") + Fmt.its([s.gpuLed ? nil : s.gpuClause]),
                    fixes: [(bundle.map { Fix.openApp("find", "Find the busy tab", bundle: $0, steps: steps.joined(separator: " "), recommended: true) }
                                ?? Fix.guide("find", "Find the busy tab", "In \(app), find the busiest tab.", steps: ["Open \(app)."] + steps, recommended: true)).fixingTheCause(),
                            bundle.map { Fix(id: "quit", title: "Quit \(app)", consequence: "Closes all tabs.", kind: .quitApp($0)).losingWork() },
                            Card.lookUp(e.name, recommended: false),
                            Card.wait(until: nil, now: s.now, recommended: false)].compactMap { $0 })
    }
}
