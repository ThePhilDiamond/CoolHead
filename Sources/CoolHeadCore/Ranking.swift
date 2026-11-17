import Foundation

/// The golden ranking: for every sample card (`Wording.samples`), which card won, its state, its recommended option and
/// the order of its options, one line each. `coolhead selftest` fails when any line differs from the copy in
/// GoldenRanking.swift, so a change in which card or option wins, from a new card, a moved card or a changed rule,
/// fails the build until the file is rewritten (`coolhead ranking --write`) in the same pull request, where the change
/// shows in the diff for review. Clock times and wording aren't recorded here; `coolhead wording` shows the wording.
public enum Ranking {
    /// One line: sample · card · state · → recommended · every option in order.
    public static func line(_ id: String, _ c: Card) -> String {
        [id, c.cardID ?? "-", "\(c.state)", "→ " + (c.recommended?.id ?? "none"), c.fixes.isEmpty ? "no options" : c.fixes.map(\.id).joined(separator: ", ")]
            .joined(separator: " · ")
    }

    public static func lines(now: Date = Date()) -> [String] { Wording.samples(now: now).map { line($0.0, $0.1) } }

    /// Every sample card's explanation (its Nerdy stuff "We recommend …" line, see Decision.swift), one line each, with
    /// clock times as "TIME" since the samples are made relative to now.
    public static func explanationLines(now: Date = Date()) -> [String] {
        Wording.samples(now: now).compactMap { id, c in
            c.choice?.line.map { id + " · " + $0.replacingOccurrences(of: #"\b\d{1,2}(:\d{2})?(am|pm)\b"#, with: "TIME", options: .regularExpression) }
        }
    }

    /// The explanations recorded in GoldenExplanations.swift.
    public static var goldenExplanations: [String] { GoldenExplanations.text.split(separator: "\n").map(String.init) }

    /// Where GoldenExplanations.swift is, beside GoldenRanking.swift.
    public static let explanationsFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("GoldenExplanations.swift")

    /// GoldenExplanations.swift's text for these lines.
    public static func explanationsSource(_ lines: [String]) -> String {
        """
        // Written by `coolhead ranking --write`; checked by `coolhead selftest` (see Ranking.swift). One line per sample
        // card that explains its recommendation: sample · the Nerdy stuff text, generated from the decision record
        // (Decision.swift), clock times as TIME. Rewrite it in the pull request that changes a line, so the change shows
        // in the diff.
        enum GoldenExplanations {
            static let text = #\"\"\"
        \(lines.map { "    " + $0 }.joined(separator: "\n"))
            \"\"\"#
        }

        """
    }

    /// The lines recorded in GoldenRanking.swift.
    public static var golden: [String] { GoldenRanking.text.split(separator: "\n").map(String.init) }

    /// Where GoldenRanking.swift is, in the source folder this copy was built from (for `coolhead ranking --write`).
    public static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("GoldenRanking.swift")

    /// GoldenRanking.swift's text for these lines.
    public static func source(_ lines: [String]) -> String {
        """
        // Written by `coolhead ranking --write`; checked by `coolhead selftest` (see Ranking.swift). One line per sample
        // card: sample · card · state · → recommended option · every option in order. Rewrite it in the pull request
        // that changes a line, so the change shows in the diff.
        enum GoldenRanking {
            static let text = #\"\"\"
        \(lines.map { "    " + $0 }.joined(separator: "\n"))
            \"\"\"#
        }

        """
    }

    /// The lines that differ from the golden file: what it records and what the samples give now.
    public static func differences(now: Date = Date()) -> (removed: [String], added: [String]) {
        let now = lines(now: now), gold = golden
        return (gold.filter { !now.contains($0) }, now.filter { !gold.contains($0) })
    }
}
