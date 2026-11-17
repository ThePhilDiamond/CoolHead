import Foundation

/// On a busy WindowServer, apps with an Electron that lags macOS 26.0 and 26.1 (see AppBuild): updating them is the
/// fix, so it's put first and recommended.
enum ElectronExtra: CardExtra {
    static let id = "electron"
    static let rule = "AppBuild.swift: older Electron apps keep WindowServer busy on macOS 26.0 and 26.1"

    static func add(to c: Card, _ s: Situation) -> Card? {
        let e = s.e
        guard let f = s.apps, s.disguise == nil, c.state != .quiet,
              Pattern.match(name: e.name, path: e.path, pid: e.pid)?.id == "windowserver",
              let add = AppBuild.electronAddition(f) else { return nil }
        let others = c.fixes.map { f -> Fix in var f = f; f.recommended = false; return f }
        var out = Card(state: c.state, headline: c.headline, explanation: c.explanation + add.sentence, fixes: [add.fix] + others)
        // the decision record: what it saw is now the apps, and updating them is what helps
        let names = String(add.fix.title.dropFirst("Update ".count))
        out.diagnosis = Diagnosis(saw: "\(names) \(names.contains(" and ") ? "are" : "is") built on an older Electron that makes this version of macOS draw slowly")
        out.optionFacts[add.fix.id] = OptionFacts(helps: "gets versions built on a newer Electron, which fix the slowdown")
        return out
    }
}
