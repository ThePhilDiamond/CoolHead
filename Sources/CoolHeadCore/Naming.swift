import Foundation

/// How a card names the processes it talks about, the same way on every card.
///
/// A name is kept short where it is clear ("Google Chrome", "train.py", "claude"). When two names on one card can't be
/// told apart (the same apart from capital letters) and are different kinds of thing, each says what it is: "the
/// Claude app" and "the claude command-line program". Two of the same kind and name: the first keeps its name, the
/// rest are "another claude". Names keep their own spelling: "macOS" and "claude" are never capitalised; only a leading "the",
/// "a" or "another" is, when it starts a sentence. The rule is general, for every card, not a fix for the one that
/// showed the problem: the memory card had said "Claude (2.7 GB) and claude (1.5 GB)". `Card.names` records what a card
/// named, and the selftest check `names-tell-apart` runs over every example card.
public enum Naming {
    /// What a process is, as a person would say it.
    public enum What: Equatable {
        case app            // an app in an .app bundle
        case script         // a script, named by its project or file
        case commandLine    // a program run from a terminal
        case background     // a program that isn't an app and has no terminal
        case macOS          // part of macOS
    }

    public struct Named: Equatable {
        public let name: String
        public let what: What
        public init(_ name: String, _ what: What) { self.name = name; self.what = what }
    }

    /// What a program that isn't an app is: run from a terminal, part of macOS, or running in the background.
    public static func what(path: String?, hasTerminal: Bool) -> What {
        if let p = path, CaseReport.isMacOS(p) { return .macOS }
        return hasTerminal ? .commandLine : .background
    }

    /// The name with what it is, for when it must be told apart from another.
    public static func described(_ n: Named) -> String {
        switch n.what {
        case .app: return "the \(n.name) app"
        case .script: return n.name.hasPrefix("a ") ? n.name : "the \(n.name) script"
        case .commandLine: return "the \(n.name) command-line program"
        case .background: return "the \(n.name) background program"
        case .macOS: return "macOS's \(n.name)"
        }
    }

    /// The names to show for processes mentioned on one card, in the same order: short where they are clear, and
    /// told apart where they aren't.
    public static func distinct(_ names: [Named]) -> [String] {
        var out = names.map(\.name)
        let key = { (s: String) in s.lowercased() }
        // 1. names alike ignoring case, for different kinds of thing: each says what it is
        let clashing = Dictionary(grouping: names.indices, by: { key(names[$0].name) }).values
            .filter { g in g.count > 1 && Set(g.map { "\(names[$0].what)" }).count > 1 }
        for group in clashing { for i in group { out[i] = described(names[i]) } }
        // 2. still alike (same name and kind): the first keeps it, the rest are "another …"
        var seen = Set<String>()
        for i in out.indices {
            if seen.insert(key(out[i])).inserted { continue }
            out[i] = another(names[i])
            seen.insert(key(out[i]))
        }
        return out
    }

    static func another(_ n: Named) -> String {
        if n.name.hasPrefix("a ") { return "another " + n.name.dropFirst(2) }
        switch n.what {
        case .app: return "another copy of \(n.name)"
        case .macOS: return "another of macOS's \(n.name)"
        default: return "another \(n.name)"
        }
    }

    /// Whether the names a card shows can all be told apart.
    public static func tellApart(_ shown: [String]) -> Bool {
        Set(shown.map { $0.lowercased() }).count == shown.count
    }
}
