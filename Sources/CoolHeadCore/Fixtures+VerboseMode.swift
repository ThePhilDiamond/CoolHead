import Foundation

/// Checks for verbose mode (docs/CARD-TEMPLATE.md, Verbose mode): the key readings a card shows in place of its
/// explanation (`NerdyStuff.key`), on every made-up card with Nerdy stuff, and the headline with its figure
/// (`CardTemplate.Reading.verboseWords`), on every sample card.
extension Fixture {
    static func verboseModeSamples(_ now: Date) -> [(String, Card)] { [] }

    static func verboseModeChecks(_ now: Date) -> [(String, Bool, String)] {
        var bad: [String] = []
        let made: [(String, NerdyStuff)] = Wording.nerdySamples(now: now).map { ($0.key, $0.value) }
            + nerdyLiveSamples(now).compactMap { id, c in c.nerdy.map { (id, $0) } }
        let sources = NerdyStuff.Source.allCases.map(\.rawValue)
        // every family's card carries its slots, or verbose mode has nothing to show on it; busy cards as the watcher
        // makes them
        for (id, c) in nerdyLiveSamples(now) where c.nerdy == nil { bad.append("\(id): no key readings (its Nerdy stuff is not set from its slots)") }
        for f in Fixture.all(now) {
            let lc = Watcher.busyCard(f.evidence, pid: f.evidence.pid, card: Card.make(f.evidence, now: now), busySince: now.addingTimeInterval(-f.busyFor),
                                      now: now, alsoBusy: [], log: [])
            if lc.nerdy == nil || lc.details.isEmpty { bad.append("\(f.id): the watcher's busy card has no key readings") }
            // CPU by its figure alone, not how it was averaged
            if let cpu = lc.nerdy?.key().first(where: { $0.name == "CPU" }), cpu.value.range(of: #"^\d+\.\d\d cores \(\d+% in Activity Monitor\)$"#, options: .regularExpression) == nil {
                bad.append("\(f.id): CPU is not its figure alone (\(cpu.value))")
            }
        }
        // readings with one name share a row
        var w = NerdyStuff(); w.saw = [.init("Writing", "a.log", .openFiles), .init("Writing", "b.bin", .openFiles)]
        if w.key().map(\.name) != ["Writing"] || w.key().first?.value != "a.log; b.bin" { bad.append("made up: two files written are not one row (\(w.key()))") }
        for (id, n) in made.sorted(by: { $0.0 < $1.0 }) {
            let key = n.key()
            let names = key.map(\.name)
            // every reading, by its figure alone where it has one; then the first list, what it is, and the rule
            for r in n.saw where !key.contains(where: { $0.name == r.name && $0.value.components(separatedBy: "; ").contains(r.brief ?? r.value) }) {
                bad.append("\(id): \(r.name) is not among the key readings as its figure")
            }
            // the first list: its first three rows, no more
            if let l = n.lists.first, !l.rows.isEmpty {
                let three = l.rows.prefix(3).map { $0.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression) }.joined(separator: "; ")
                if !key.contains(where: { l.title.hasPrefix($0.name) && $0.value == three }) { bad.append("\(id): the first list is not its first three rows") }
            }
            if let i = n.identity.first, !key.contains(where: { i.hasPrefix($0.name + ": ") }) { bad.append("\(id): what it is is missing") }
            if let v = n.verdict.first, !key.contains(where: { $0.name == "Rule" && $0.value == v }) { bad.append("\(id): the rule is missing") }
            if Set(names).count != names.count { bad.append("\(id): two rows share a name") }
            // the sources and Terminal checks stay in Nerdy stuff: a source as a reading's tag, "(source, 10:09pm)" or
            // "(source)", not a word in a rule ("ps state T")
            for r in key where sources.contains(where: { r.value.contains("(\($0),") || r.value.contains("(\($0))") }) || r.value.contains("check:") {
                bad.append("\(id): \(r.name) shows its source or check")
            }
            for r in key where r.value.isEmpty { bad.append("\(id): \(r.name) is empty") }
            for p in CardTemplate.clarity(key.map { "\($0.name): \($0.value)" }.joined(separator: "\n")) { bad.append("\(id): \(p)") }
        }
        // a card's Nerdy stuff, set from its slots, is written from them
        var c = LiveCard(id: "x", pid: nil, card: Card(state: .working, headline: "", explanation: "", fixes: []), details: ["old"])
        if let n = made.first?.1 { c.nerdy = n; if c.details != n.lines() { bad.append("setting a card's slots does not write its Nerdy stuff") } }
        // the headline: a reading with a figure shows it; every headline keeps the word list
        var figures = 0
        for (id, card) in Wording.samples(now: now) {
            guard let t = card.template, let r = t.reading else { continue }
            let v = card.verboseHeadline
            switch r {
            case .coresNow, .coresUnderLimit, .coresFor, .graphicsFor:
                figures += 1
                if v == card.headline || v.range(of: #"\d"#, options: .regularExpression) == nil { bad.append("\(id): the verbose headline has no figure") }
            default:
                if v != card.headline { bad.append("\(id): the verbose headline changed a reading with no figure") }
            }
            for p in CardTemplate.clarity(v) { bad.append("\(id) verbose headline: \(p)") }
        }
        if figures == 0 { bad.append("no sample headline has a figure to show") }
        return [("verbose-mode", bad.isEmpty,
                 bad.isEmpty ? "\(made.count) cards' key readings and \(figures) headlines with a figure" : bad.prefix(6).joined(separator: "; "))]
    }
}
