import Foundation

/// Checks for the cues that help you choose an option (docs/CARD-TEMPLATE.md, Option cues): the tag every option shows
/// for what it does about the problem, and the line under the recommended option saying why it was chosen. Runs over
/// every example card, the same list `coolhead wording` prints.
extension Fixture {
    static func optionCuesSamples(_ now: Date) -> [(String, Card)] { [] }

    static func optionCuesChecks(_ now: Date) -> [(String, Bool, String)] {
        let samples = Wording.samples(now: now)
        let byID = Dictionary(samples.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        // every option's tag is from the closed list
        let offList = samples.flatMap { s in s.1.fixes.filter { !Fix.impacts.contains($0.impact) }.map { "\(s.0): \($0.title) \"\($0.impact)\"" } }
        // what each why line says is true of the facts it comes from, read back from the sentence: a check written apart
        // from the code that writes it
        var untrue: [String] = []
        for (id, c) in samples {
            guard let w = c.why, let r = c.recommended else { continue }
            let others = c.fixes.filter { $0.kind.isAction && $0.id != r.id }
            // every option that acts and does as much: each reason must hold against all of them
            let rivals = others.filter { $0.result >= r.result }
            if w.contains("in one click"), r.doer != .coolHead { untrue.append("\(id): one click, but a task for you") }
            if w.contains("in one click"), r.caution { untrue.append("\(id): one click, but Caution asks twice") }
            if w.contains("in one click"), let o = rivals.first(where: { $0.doer == .coolHead }) { untrue.append("\(id): one click, but so is \(o.title)") }
            if w.contains("without closing anything"), r.doer == .you { untrue.append("\(id): closes nothing, but it is a task done your way") }
            if w.contains("without closing anything"), r.closesSomething { untrue.append("\(id): closes nothing, but it closes something") }
            if w.contains("without closing anything"), let o = rivals.first(where: { !$0.closesSomething }) { untrue.append("\(id): closes nothing, but neither does \(o.title)") }
            if w.contains("only option"), others.contains(where: { $0.result >= r.result }) { untrue.append("\(id): the only option, but another does as much") }
            if w != "Cool Head recommends this.", w.contains("fixes the cause") != (r.result == .fixesCause) { untrue.append("\(id): what it does doesn't match its tag") }
            if r.result == .informs, w != "Cool Head recommends this." { untrue.append("\(id): a reason for an option that only tells you more") }
        }
        // every recommendation has the line, since nothing else says it in words
        let unmarked = samples.filter { $0.1.recommended != nil && $0.1.why == nil }.map(\.0)
        // a Caution option asks twice, so it's never "in one click", even where every rival is a task (no sample has one)
        let stopIt = Fix(id: "stop", title: "Stop it", consequence: "This stops it.", kind: .stop, recommended: true)
        let byHand = Fix(id: "byhand", title: "Close it", consequence: "This opens it.", kind: .openApp("/Applications/Safari.app", "Close it.")).fixingTheCause()
        if let w = Card(state: .stalled, headline: "x", explanation: "", fixes: [stopIt, byHand]).why, w.contains("in one click") { untrue.append("made-up card: one click on Caution (\(w))") }
        let says = "Cool Head recommends this because it "
        let expected: [(String, String?)] = [
            ("chrome-tab", "Cool Head recommends this."),          // Close just that tab is one click too, and a task closes nothing either
            ("memory-chrome-grown", "Cool Head recommends this."), // Caution asks twice, and Quit Google Chrome is one click too
            ("intel-app-27", says + "helps in one click."),        // the other option that helps is a task
            ("job-no-signs", says + "helps without closing anything."),   // Stop it, one click too, closes it
            ("kernel-task-long", says + "is the only option that helps."),
            ("web-page-in-app", says + "is the only option that fixes the cause."),
            ("app-on-the-graphics-chip", "Cool Head recommends this."),   // Search the web: Quit Blender isn't put forward, since Cool Head can't tell what it's doing
            ("catalogue-displaylink-long", "Cool Head recommends this."),   // the restart, one click: Quit is one click and fixes the cause too
            ("stuck-after-restart", "Cool Head recommends this."),   // two tasks that help: nothing in the facts says why one won
            ("job-stalled", "Cool Head recommends this."),           // Stop it is the only option that acts
            ("spotlight-long", "Cool Head recommends this."),        // it only tells you more
            ("job-just-started", nil),                               // nothing recommended: it is working normally
        ]
        let wrong = expected.filter { byID[$0.0]?.why != $0.1 }.map { "\($0.0): \(byID[$0.0].map { $0.why ?? "no line" } ?? "no such card")" }
        // setting up the extension helps later, not now
        let later = byID["memory-chrome-get-companion"]?.fixes.first { if case .chromeCompanion("setup") = $0.kind { return true }; return false }?.impact
        let recs = samples.filter { $0.1.recommended != nil }
        let reasons = samples.compactMap(\.1.why).filter { $0 != "Cool Head recommends this." }
        let counts = Fix.impacts.map { i in "\(i) \(samples.flatMap(\.1.fixes).filter { $0.impact == i }.count)" }.joined(separator: ", ")
        let ok = offList.isEmpty && untrue.isEmpty && unmarked.isEmpty && wrong.isEmpty && later == "Helps later"
        // once the recommended option is done: it goes, the next is the card's own pick where one click took its place,
        // else the first option left that acts and isn't Caution; never a Caution option; one at most, with its line
        var journey: [String] = []
        var nexts: [String] = []
        for (id, c) in samples {
            guard let r = c.recommended else { if c.after(["x"]).recommended != nil { journey.append("\(id): a recommendation where there was none") }; continue }
            let a = c.after([r.doneKey])
            if a.fixes.contains(where: { $0.id == r.id }) { journey.append("\(id): \(r.title) still offered once done") }
            if a.fixes.filter(\.recommended).count > 1 { journey.append("\(id): more than one next") }
            let left = c.fixes.filter { $0.id != r.id }
            let want = c.displaced.flatMap { d in left.first { $0.id == d && !$0.caution } } ?? left.first { $0.kind.isAction && !$0.caution && !$0.holdBack && !(c.state == .unknown && $0.interrupts) }
            if a.recommended?.id != want?.id { journey.append("\(id): next is \(a.recommended?.title ?? "none"), not \(want?.title ?? "none")") }
            if a.recommended?.caution == true { journey.append("\(id): a Caution option put forward") }
            if a.recommended?.holdBack == true { journey.append("\(id): a held-back option put forward") }
            if a.recommended != nil, a.why == nil { journey.append("\(id): the next has no line") }
            if a.recommended.map({ $0.id != a.fixes.first?.id }) ?? false { journey.append("\(id): the next isn't first") }
            if let n = a.recommended { nexts.append("\(id) → \(n.title)") }
            if c.after([]).fixes.map(\.id) != c.fixes.map(\.id) || c.after([]).recommended?.id != r.id { journey.append("\(id): changed with nothing done") }
            // another option done leaves the recommendation where it is
            for o in c.fixes where o.id != r.id {
                if c.after([o.doneKey]).recommended?.id != r.id { journey.append("\(id): \(o.title) done moved the recommendation"); break }
            }
            // and two in turn: the next after the next
            if let n = a.recommended {
                let b = c.after([r.doneKey, n.doneKey])
                if b.fixes.contains(where: { $0.id == n.id }) || b.recommended?.caution == true || b.fixes.filter(\.recommended).count > 1 { journey.append("\(id): second step wrong") }
            }
        }
        let expectedNext: [(String, String?)] = [
            ("catalogue-displaylink-long", "Search the web"),   // Quit DisplayLink Manager isn't put forward: Cool Head can't tell what it's doing
            ("app-on-the-graphics-chip", nil),                  // the same for Quit Blender, and nothing else acts
            ("job-stalled", nil),                                            // nothing left that acts
        ]
        for (id, t) in expectedNext {
            guard let c = byID[id], let r = c.recommended else { journey.append("\(id): no such card or no recommendation"); continue }
            if c.after([r.doneKey]).recommended?.title != t { journey.append("\(id): next is \(c.after([r.doneKey]).recommended?.title ?? "none")") }
        }
        // two rules no sample card tells apart, on made-up cards. The card's own pick comes back next even where
        // another option left would come first in the card's order (a task that fixes the cause):
        let own = Fix(id: "own", title: "Find it", consequence: "This shows the steps.", kind: .guide(["Open it."]), recommended: true)
        let more = Fix(id: "more", title: "Open it", consequence: "This opens it.", kind: .openApp("/Applications/Safari.app", "Close it.")).fixingTheCause()
        let fast = Fix(id: "fast", title: "Run it cooler", consequence: "This slows it.", kind: .cooler)
        let made = Card(state: .unknown, headline: "x", explanation: "", fixes: [own, more, fast])
        if made.recommended?.id != "fast" { journey.append("made-up card: \(made.recommended?.id ?? "none") recommended, not the one-click option") }
        if made.after([fast.doneKey]).recommended?.id != "own" { journey.append("made-up card: next is \(made.after([fast.doneKey]).recommended?.id ?? "none"), not the card's own pick") }
        // and still, with a sentence added to the card (Card.adding makes a new card)
        if made.adding(effect: "It adds heat.").after([fast.doneKey]).recommended?.id != "own" { journey.append("made-up card: the card's own pick lost by adding a sentence") }
        // done is what an option acts on, not its id: Quit Slack done doesn't hide Quit Xcode, which reuses the id
        let quitSlack = Fix(id: "quit", title: "Quit Slack", consequence: "This quits it.", kind: .quitApp("/Applications/Slack.app"), recommended: true)
        let quitXcode = Fix(id: "quit", title: "Quit Xcode", consequence: "This quits it.", kind: .quitApp("/Applications/Xcode.app"), recommended: true)
        if !Card(state: .unknown, headline: "x", explanation: "", fixes: [quitXcode]).after([quitSlack.doneKey]).fixes.contains(where: { $0.title == "Quit Xcode" }) {
            journey.append("made-up card: Quit Xcode hidden by Quit Slack done")
        }
        // a held-back option is never the next: the cooler for a virtual machine, say
        var held = fast; held.holdBack = true
        let stop = Fix(id: "stop", title: "Stop it", consequence: "This stops it.", kind: .stop, recommended: true)
        let look = Fix(id: "lookup", title: "Search the web", consequence: "This searches.", kind: .lookUp("x"))
        if Card(state: .unknown, headline: "x", explanation: "", fixes: [look, held, stop]).after([stop.doneKey]).recommended?.holdBack == true {
            journey.append("made-up card: a held-back option put forward")
        }
        // and an option in one click that only tells you more gives way to one in one click that helps
        let setup = Fix(id: "setup", title: "Set up", consequence: "This sets it up.", kind: .chromeCompanion("setup"), recommended: true)
        let informs = Card(state: .unknown, headline: "x", explanation: "", fixes: [setup, fast])
        if informs.recommended?.id != "fast" { journey.append("made-up card: \(informs.recommended?.id ?? "none") recommended over one click that helps") }
        // a restart the catalogue advises is one click where Cool Head can quit the app (DisplayLink Manager)
        let restartsItself: Bool = { if case .restartApp = byID["catalogue-displaylink-long"]?.recommended?.kind { return true }; return false }()
        if !restartsItself {
            journey.append("catalogue-displaylink-long: the restart isn't one click")
        }
        let ok2 = journey.isEmpty
        // Quit beside a restart of the same app says when it's the one to use; a quit with no restart beside it doesn't
        var quits: [String] = []
        var said = 0
        for (id, c) in samples {
            let restarted = Set(c.fixes.compactMap(\.restarts))
            for f in c.fixes {
                guard case .quitApp(let b) = f.kind else { continue }
                let says = f.consequence.hasPrefix(Card.whenDoneWords)
                if restarted.contains(b) { if says { said += 1 } else { quits.append("\(id): \(f.title) beside its restart doesn't say when") } }
                else if says { quits.append("\(id): \(f.title) says when with no restart beside it") }
            }
        }
        if said == 0 { quits.append("no example card has a quit beside a restart") }
        let mk = { (bundle: String) in Card(state: .unknown, headline: "x", explanation: "", fixes: [
            Fix(id: "restart", title: "Restart A", consequence: "This quits it and opens it again.", kind: .restartApp("/A.app"), recommended: true),
            Fix(id: "quit", title: "Quit", consequence: "This quits it.", kind: .quitApp(bundle))]) }
        if mk("/A.app").fixes.first(where: { $0.id == "quit" })?.consequence != "Use this only if you are no longer using it. This quits it." { quits.append("made-up card: the quit beside its restart") }
        if mk("/B.app").fixes.first(where: { $0.id == "quit" })?.consequence != "This quits it." { quits.append("made-up card: a quit of another app changed") }
        let twice = mk("/A.app").adding(effect: "It is busy.")
        if twice.fixes.first(where: { $0.id == "quit" })?.consequence.components(separatedBy: Card.whenDoneWords).count != 2 { quits.append("made-up card: said twice after adding") }
        // the words go when the restart does: after it's done, and when the card is then rebuilt with a sentence added
        for (id, c) in samples {
            // each restart done in turn, then both: the words stay only while a restart of the same app is left
            let restartKeys = c.fixes.filter { $0.restarts != nil }.map(\.doneKey)
            for done in restartKeys.map({ Set([$0]) }) + (restartKeys.count > 1 ? [Set(restartKeys)] : []) {
                for left in [c.after(done), c.after(done).adding(effect: "It is busy.")] {
                    let restarted = Set(left.fixes.compactMap(\.restarts))
                    for f in left.fixes {
                        guard case .quitApp(let b) = f.kind else { continue }
                        if f.whenDone != restarted.contains(b) { quits.append("\(id): after \(done.count) done, \(f.title) says when: \(f.whenDone)") }
                    }
                }
            }
        }
        let ok3 = quits.isEmpty
        return [("option-cues", ok,
                 ok ? "\(samples.count) example cards; tags: \(counts); a line on all \(recs.count) recommended options, \(reasons.count) with a reason, each true of its facts"
                    : "off the list: \(offList); untrue: \(untrue); no line: \(unmarked); unexpected: \(wrong); setup: \(later ?? "not offered")"),
                ("option-done-then-next", ok2, ok2 ? "\(nexts.count) cards put the next option forward once the recommended one is done, none Caution" : journey.joined(separator: "; ")),
                ("quit-beside-restart", ok3, ok3 ? "\(said) quits beside a restart of the same app say \"\(Card.whenDoneWords)\"; none elsewhere, nor once the restart is done" : quits.joined(separator: "; "))]
    }
}
