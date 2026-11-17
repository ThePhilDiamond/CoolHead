import Foundation

/// Web pages shown by another app (Mail, or an app with a web view): WebKit's processes do the work for it, and
/// quitting that app is the advice (see Served.swift).
enum WebPageInAppCard: ProcessCard {
    static let name = "a web page in an app"
    static let id = "web-page-in-app"
    static let kind = CardKind.explanation
    static let rule = "Research rule 4: WebKit's work is credited to the app whose pages it shows"
    static func confidence(_ s: Situation) -> Confidence { .named("macOS says which app is showing this web page") }
    static let samples = ["web-page-in-app"]

    static func card(_ s: Situation) -> Card? {
        let e = s.e
        guard s.webkit, let b = e.servedBy, !Served.isSafari(b), s.active else { return nil }
        let app = Served.name(b)
        return Card(state: s.busyFor > 20 * 60 ? .unknown : .working,
                    headline: s.webkitGPU ? "A web page in \(app) is drawing a lot: video or animation." : "A web page in \(app) is working hard.",
                    explanation: "macOS \(s.webkitGPU ? "draws" : "runs") \(app)'s web pages in a separate process, which \(s.used)"
                        + Fmt.its([s.gpuLed ? nil : s.gpuClause, s.warm && s.heating ? "adding to the heat" : nil]),
                    fixes: [Served.quit(b), Card.lookUp(e.name, recommended: false), Card.wait(until: nil, now: s.now, recommended: false)])
    }
}
