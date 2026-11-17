import Foundation

/// Checks for how cards name processes (see Naming.swift). Runs over every example card, the same list
/// `coolhead wording` prints, so a card that names two things alike fails here whichever card it is.
extension Fixture {
    static func namingChecks(_ now: Date) -> [(String, Bool, String)] {
        let samples = Wording.samples(now: now)
        var bad: [String] = []
        for (id, c) in samples {
            let text = ([c.headline, c.explanation] + c.facts + c.fixes.flatMap { [$0.title, $0.consequence] }).joined(separator: " ")
            if !Naming.tellApart(c.names) { bad.append("\(id): \(c.names) can't be told apart") }
            for n in c.names where !text.contains(n) && !text.contains(Fmt.sentenceStart(n)) { bad.append("\(id): names \"\(n)\" but doesn't show it") }
        }
        let named = samples.filter { !$0.1.names.isEmpty }.count
        let aboutProcesses = samples.filter { !$0.0.hasPrefix("hardware-") }.count      // hardware cards name no process
        // the cases that started it: an app and a program alike; a program first in a sentence; a child of the same name
        func card(_ id: String) -> Card? { samples.first { $0.0 == id }?.1 }
        let alike = card("memory-app-and-program-alike")
        let first = card("memory-program-first")
        let child = card("hang-started-a-program-of-its-own-name")
        let cases = alike?.headline == "Memory is tight. The Claude app is using the most (2.7 GB)."
            && alike?.facts == ["Also using a lot: the claude command-line program (1.5 GB)"]
            && first?.headline.hasPrefix("Memory is tight. node is using the most") == true
            && child?.explanation.contains("another ffmpeg and ffprobe") == true
            && Naming.distinct([.init("a script", .script), .init("a script", .script)]) == ["a script", "another script"]
            && Fmt.sentenceStart("macOS's mds") == "macOS's mds" && Fmt.sentenceStart("the claude command-line program") == "The claude command-line program"
        return [("names-tell-apart", bad.isEmpty && cases && named >= aboutProcesses * 2 / 3,
                 bad.isEmpty ? "\(named) of \(aboutProcesses) example cards about processes record their names; all can be told apart; cases \(cases)" : bad.joined(separator: "; "))]
    }
}
