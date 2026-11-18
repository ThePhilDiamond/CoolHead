import Foundation

/// Checks for underlined menu items (see MenuWords.swift): marks come in pairs around a name, plain text drops them,
/// and every example card's options, steps and notes keep them balanced, so the app never draws a stray mark.
extension Fixture {
    static func menuWordsChecks(_ now: Date) -> [(String, Bool, String)] {
        let s = "Click \(Fmt.ui("Window")), then \(Fmt.path("Apple menu", "Restart"))."
        let runs = Fmt.uiRuns(s).map { $0.underlined ? "_\($0.text)_" : $0.text }.joined()
        var bad: [String] = []
        for (id, c) in Wording.samples(now: now) {
            for f in c.fixes {
                var texts = [f.consequence]
                if case .guide(let steps) = f.kind { texts += steps }
                if case .openApp(_, let steps) = f.kind { texts.append(steps) }
                for t in texts where !balanced(t) { bad.append("\(id) \(f.id): \(Fmt.plain(t))") }
            }
        }
        let wording = Wording.samples(now: now).map { Wording.text($0.1) }.joined()
        let ok = Fmt.plain(s) == "Click Window, then Apple menu ▸ Restart." && runs == "Click _Window_, then _Apple menu_ ▸ _Restart_."
            && bad.isEmpty && !wording.contains(Fmt.uiOpen) && !wording.contains(Fmt.uiClose)
        return [("menu-words-underlined", ok, bad.isEmpty ? runs : bad.joined(separator: "; "))]
    }

    /// Each opening mark is closed before the next opens, and the text ends outside a name.
    static func balanced(_ t: String) -> Bool {
        var inside = false
        for ch in t {
            if ch == Fmt.uiOpen { if inside { return false }; inside = true }
            if ch == Fmt.uiClose { if !inside { return false }; inside = false }
        }
        return !inside
    }

    /// No sample cards of its own for `coolhead wording`.
    static func menuWordsSamples(_ now: Date) -> [(String, Card)] { [] }
}
