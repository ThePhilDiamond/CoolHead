import Foundation

/// Checks for how options are grouped and labelled (see `Fix.doer`, `Fix.caution`, `Card.betterThanRecommended`). Runs
/// over every example card, the same list `coolhead wording` prints.
extension Fixture {
    static func optionChecks(_ now: Date) -> [(String, Bool, String)] {
        let samples = Wording.samples(now: now)
        var bad: [String] = []
        for (id, c) in samples {
            for f in c.fixes {
                // one corner label at most: Caution is for what Cool Head does, Fixes the cause for your tasks
                if f.caution && f.doer == .you { bad.append("\(id): \(f.title) is a task for you labelled Caution") }
                if f.caution && c.betterThanRecommended.contains(where: { $0.id == f.id }) { bad.append("\(id): \(f.title) would get both labels") }
            }
            if c.fixes.filter(\.recommended).count > 1 { bad.append("\(id): more than one recommendation") }
            // one click first: a task is recommended only when no one-click option eases it without interrupting
            if let r = c.recommended, r.doer == .you,
               let alt = c.fixes.first(where: { $0.doer == .coolHead && !$0.interrupts && !$0.holdBack && $0.result >= .eases }) {
                bad.append("\(id): recommends the task \(r.title) over \(alt.title)")
            }
        }
        let caution = samples.filter { $0.1.fixes.contains(where: \.caution) }.count
        let better = samples.filter { !$0.1.betterThanRecommended.isEmpty }.count
        let recs = samples.compactMap(\.1.recommended)
        let labelled = "\(caution) with a Caution option, \(better) with a task that fixes the cause; recommendations: \(recs.count), "
            + "\(recs.filter { $0.doer == .coolHead && !$0.caution }.count) one click and safe, \(recs.filter(\.caution).count) Caution, \(recs.filter { $0.doer == .you }.count) tasks"
        // Caution only where there's risk (Phil, 16 November 2026: "Caution should be reserved for actions like killing a
        // process with unknown and/or irreversible consequences. There is risk attached. Whereas quitting Slack is not
        // risky..."): quitting an app that asks to save, or one that loses nothing (Slack, a sync app, music), isn't
        // Caution, and is recommended when it's the way to free memory; quitting what loses work in progress (containers,
        // a call, a terminal, a game, a browser's tabs), stopping, force quitting and restarting a browser are
        var tight = MacState(); tight.memoryPressure = "warning"
        func quit(_ name: String, _ kind: MemGroup.Kind = .app) -> Fix? {
            MemoryAdvice.card([MemGroup(key: name, name: name, kind: kind, bundle: "/Applications/\(name).app", bytes: 3_000_000_000, count: 3)],
                              mac: tight, now: now, chrome: .unavailable).fixes.first { $0.id == "quit" }
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
        return [("option-labels", bad.isEmpty,
                 bad.isEmpty ? "\(samples.count) example cards: at most one corner label per option, one click first; \(labelled)" : bad.joined(separator: "; ")),
                ("caution-only-when-risky", wrongCalm.isEmpty && wrongRisky.isEmpty && alwaysRisky.isEmpty && gameQuitRisky,
                 "no Caution, recommended: \(calm.map(\.0).joined(separator: ", ")); Caution, not recommended: \(risky.map(\.0).joined(separator: ", ")); "
                 + "wrong: \(wrongCalm + wrongRisky), kinds without Caution \(alwaysRisky.count), game quit Caution \(gameQuitRisky)")]
    }
}
