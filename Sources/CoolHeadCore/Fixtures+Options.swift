import Foundation

/// Checks for how options are grouped and labelled (see `Fix.doer`, `Fix.caution`, `Card.betterThanRecommended`). Runs
/// over every example card, the same list `coolhead wording` prints.
extension Fixture {
    static func optionsChecks(_ now: Date) -> [(String, Bool, String)] {
        let samples = Wording.samples(now: now)
        var bad: [String] = []
        for (id, c) in samples {
            for f in c.fixes {
                // Caution is for what Cool Head does: a task for you is done your own way, with its own care
                if f.caution && f.doer == .you { bad.append("\(id): \(f.title) is a task for you labelled Caution") }
            }
            if c.fixes.filter(\.recommended).count > 1 { bad.append("\(id): more than one recommendation") }
            // one click first: a task, or an option that only tells you more, is recommended only when no option in one
            // click helps without Caution (and, where the card can't tell what it's doing, without closing it)
            if let r = c.recommended, r.doer == .you || r.result < .eases,
               let alt = c.fixes.first(where: { $0.doer == .coolHead && !$0.caution && !$0.holdBack && $0.result >= .eases && !(c.state == .unknown && $0.interrupts) }) {
                bad.append("\(id): recommends \(r.title) over \(alt.title), one click")
            }
        }
        let caution = samples.filter { $0.1.fixes.contains(where: \.caution) }.count
        let better = samples.filter { !$0.1.betterThanRecommended.isEmpty }.count
        let recs = samples.compactMap(\.1.recommended)
        let labelled = "\(caution) with a Caution option, \(better) with a task that fixes the cause; recommendations: \(recs.count), "
            + "\(recs.filter { $0.doer == .coolHead && !$0.caution }.count) one click and safe, \(recs.filter(\.caution).count) Caution, \(recs.filter { $0.doer == .you }.count) tasks"
        // Caution only where there's risk, such as stopping a process with unknown or irreversible consequences: quitting
        // an app that asks to save, or one that loses nothing (Slack, a sync app, music), isn't Caution, and is
        // recommended when it's the way to free memory; quitting what loses work in progress (containers, a call, a
        // terminal, a game, a browser's tabs), stopping, force quitting, and restarting a browser are Caution
        var tight = MacState(); tight.memoryPressure = "warning"
        func quit(_ name: String, _ kind: MemGroup.Kind = .app) -> Fix? {
            MemoryAdvice.card([MemGroup(key: name, name: name, kind: kind, bundle: "/Applications/\(name).app", bytes: 3_000_000_000, count: 3)],
                              mac: tight, now: now, tabMemoryOn: false).fixes.first { $0.id == "quit" }
        }
        let calm = ["Slack", "Spotify", "Pages", "Google Drive"].map { (n: String) in (n, quit(n)) }
        let risky = [("Docker", quit("Docker")), ("zoom.us", quit("zoom.us")), ("Terminal", quit("Terminal")), ("Google Chrome", quit("Google Chrome", .browser))]
        let wrongCalm = calm.filter { $0.1 == nil || $0.1!.caution || !$0.1!.recommended }.map(\.0)
        let wrongRisky = risky.filter { $0.1 == nil || !$0.1!.caution || $0.1!.recommended }.map(\.0)
        let alwaysRisky = [Fix.Kind.stop, .forceQuit, .restartBrowser("/Applications/Google Chrome.app")]
            .filter { !Fix(id: "x", title: "", consequence: "", kind: $0).caution }
        let game = Card.make(Evidence.sample(name: "BloonsTD6", path: "/Users/x/Library/Application Support/Steam/steamapps/common/BloonsTD6/BloonsTD6.app/Contents/MacOS/BloonsTD6",
                                             start: now.addingTimeInterval(-7200), cores: 0.6), now: now, busySince: now.addingTimeInterval(-7200), warm: true)
        let gameQuitRisky = game.fixes.first { $0.id == "quit" }?.caution == true
        // from the catalogue: quitting Docker stops its containers; quitting DisplayLink Manager only darkens its screens until reopened
        func catalogueQuit(_ path: String) -> Fix? {
            Card.make(Evidence.sample(name: (path as NSString).lastPathComponent, path: path, start: now.addingTimeInterval(-7200), cores: 1.5),
                      now: now, busySince: now.addingTimeInterval(-7200), warm: true).fixes.first { $0.id == "quit" }
        }
        let dockerQuit = catalogueQuit("/Applications/Docker.app/Contents/MacOS/com.docker.backend")
        let displayQuit = catalogueQuit("/Applications/DisplayLink Manager.app/Contents/MacOS/DisplayLink Manager")
        let catalogueOK = dockerQuit?.caution == true && displayQuit?.caution == false
        return [("option-labels", bad.isEmpty,
                 bad.isEmpty ? "\(samples.count) example cards: Caution only on what Cool Head does, one click first; \(labelled)" : bad.joined(separator: "; ")),
                ("caution-only-when-risky", wrongCalm.isEmpty && wrongRisky.isEmpty && alwaysRisky.isEmpty && gameQuitRisky && catalogueOK,
                 "no Caution, recommended: \(calm.map(\.0).joined(separator: ", ")); Caution, not recommended: \(risky.map(\.0).joined(separator: ", ")); "
                 + "wrong: \(wrongCalm + wrongRisky), kinds without Caution \(alwaysRisky.count), game quit Caution \(gameQuitRisky); "
                 + "catalogue: Docker quit Caution \(dockerQuit?.caution.description ?? "not offered"), DisplayLink quit Caution \(displayQuit?.caution.description ?? "not offered")")]
            + [cautionSaysWhy(samples), textLeavesTheActionToItsOption(samples)]
    }

    /// Every Caution option, on every example card, says why when the pointer rests on its label, so no warning goes
    /// unexplained; and only Caution options have a reason.
    static func cautionSaysWhy(_ samples: [(String, Card)]) -> (String, Bool, String) {
        let fixes = samples.flatMap { s in s.1.fixes.map { (s.0, $0) } }
        let cautious = fixes.filter { $0.1.caution }
        let missing = cautious.filter { ($0.1.cautionReason ?? "").isEmpty }.map { "\($0.0): \($0.1.title)" }
        let stray = fixes.filter { !$0.1.caution && $0.1.cautionReason != nil }.map { "\($0.0): \($0.1.title)" }
        let reasons = Set(cautious.map { "\($0.1.title) → \($0.1.cautionReason ?? "")" }).sorted()
        return ("caution-says-why", !cautious.isEmpty && missing.isEmpty && stray.isEmpty,
                missing.isEmpty && stray.isEmpty ? "\(cautious.count) Caution options, each with a reason: " + reasons.joined(separator: " | ")
                    : "no reason: \(missing); reason without Caution: \(stray)")
    }

    /// A card's text gives the verdict and the evidence; the action is its recommended option, and the text doesn't
    /// repeat it, so the card doesn't say the same thing twice. A mechanical check, the option's own title in the text:
    /// a reworded repeat still needs reading for.
    static func textLeavesTheActionToItsOption(_ samples: [(String, Card)]) -> (String, Bool, String) {
        let repeats = samples.compactMap { id, c -> String? in
            guard let r = c.recommended else { return nil }
            return (c.headline + " " + c.explanation).lowercased().contains(r.title.lowercased()) ? "\(id): \(r.title)" : nil
        }
        return ("text-leaves-the-action-to-its-option", repeats.isEmpty,
                repeats.isEmpty ? "\(samples.filter { $0.1.recommended != nil }.count) cards with a recommendation; none repeats it in its text" : repeats.joined(separator: "; "))
    }

    /// No sample cards of its own for `coolhead wording`.
    static func optionsSamples(_ now: Date) -> [(String, Card)] { [] }
}
