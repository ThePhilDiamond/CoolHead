import Foundation

/// Checks for how cards name processes (see Naming.swift). Runs over every example card, the same list
/// `coolhead wording` prints, so a card that names two things alike fails here whichever card it is.
extension Fixture {
    static func namingChecks(_ now: Date) -> [(String, Bool, String)] {
        let samples = Wording.samples(now: now)
        var bad: [String] = []
        for (id, c) in samples {
            let text = ([c.headline, c.explanation] + c.facts + c.fixes.flatMap { [$0.title, $0.consequence] }).joined(separator: " ")
            if !Naming.tellApart(c.names) { bad.append("\(id): \(c.names) cannot be told apart") }
            for n in c.names where !text.contains(n) && !text.contains(Fmt.sentenceStart(n)) { bad.append("\(id): names \"\(n)\" but does not show it") }
        }
        let named = samples.filter { !$0.1.names.isEmpty }.count
        let aboutProcesses = samples.filter { !$0.0.hasPrefix("hardware-") }.count      // hardware cards name no process
        // the cases that started it: an app and a program alike; a program first in a sentence; a child of the same name
        func card(_ id: String) -> Card? { samples.first { $0.0 == id }?.1 }
        let alike = card("memory-app-and-program-alike")
        let first = card("memory-program-first")
        let child = card("hang-started-a-program-of-its-own-name")
        let cases = alike?.headline == "Apps and programs are using almost all of your Mac's memory. The Claude app uses the most, 2.7 GB."
            && alike?.facts == ["Also using a lot: the claude command-line program (1.5 GB)"]
            && first?.headline.contains("node uses the most") == true
            && child?.explanation.contains("another ffmpeg and ffprobe") == true
            && Naming.distinct([.init("a script", .script), .init("a script", .script)]) == ["a script", "another script"]
            && Fmt.sentenceStart("macOS's mds") == "macOS's mds" && Fmt.sentenceStart("the claude command-line program") == "The claude command-line program"
        return [("names-tell-apart", bad.isEmpty && cases && named >= aboutProcesses * 2 / 3,
                 bad.isEmpty ? "\(named) of \(aboutProcesses) example cards about processes record their names; all can be told apart; cases \(cases)" : bad.joined(separator: "; ")),
                // every list of three or more in a sentence takes the Oxford comma, and code builds its lists with
                // Fmt.list, not ListFormatter, which drops the comma in British English
                oxfordComma()]
    }

    static func oxfordComma() -> (String, Bool, String) {
        let lists = [Fmt.list([]), Fmt.list(["a"]), Fmt.list(["a", "b"]), Fmt.list(["a", "b", "c"]), Fmt.list(["a", "b", "c"], or: true),
                     Hang.waitingWords(["ffmpeg", "ffprobe", "node", "python3"]) ?? ""]
        let ok = lists == ["", "a", "a and b", "a, b, and c", "a, b, or c",
                           "It started 4 programs that may wait for it: ffmpeg, ffprobe, node, and others."]
        return ("lists-oxford-comma", ok, lists.joined(separator: " | "))
    }

    /// No sample cards of its own for `coolhead wording`.
    static func namingSamples(_ now: Date) -> [(String, Card)] { [] }
}
